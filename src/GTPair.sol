// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LP} from "./LP.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GTPair is LP, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error GTPair__InsufficientOutputAmount();
    error GTPair__InsufficientPoolLiquidity();
    error GTPair__CannotOutputTwoTokens();
    error GTPair__CannotBeZeroAddress();
    error GTPair__TokensCannotBeTheSame();
    error GTPair__SlippageTooHigh();
    error GTPair__DeadlinePassed();
    error GTPair__UnknownTokens();
    error GTPair__InsufficientLiquidityMinted();
    error GTPair__InsufficientLiquidityBurned();
    error GTPair__InvalidTo();
    error GTPair__InsufficientInputAmount();
    error GTPair__InvalidK(uint256 actualK, uint256 expectedK);
    error GTPair__MustBeFactory();

    address public s_token0;
    address public s_token1;

    uint112 private s_reserve0;
    uint112 private s_reserve1;
    uint32 private s_blockTimestampLast;

    address public immutable i_factory;
    address public immutable i_burnAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3; // 1,000 LP tokens
    uint256 public constant FEE = 3; // 0.3%
    uint256 public constant FEE_PRECISION = 1000;

    event Sync(uint112 reserve0, uint112 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    constructor() {
        i_factory = msg.sender;
    }

    // Called once by the factory.
    // We do not pass any constructor arguments in GTPair initalisation, because this would make addresses non-deterministic (each would have different constructor arguments)

    function initialise(address token0, address token1) external {
        if (msg.sender != i_factory) {
            revert GTPair__MustBeFactory();
        }
        s_token0 = token0;
        s_token1 = token1;
    }

    /**
     * @notice Core swap functionality
     * @param amount0Out The amount of the first token going out.
     * @param amount1Out The amount of the second token going out.
     */
    // @note This is without flash loan capability, need to come back to this.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        // One of the amount outs must be non-zero
        if (amount0Out == 0 && amount1Out == 0) {
            revert GTPair__InsufficientOutputAmount();
        }
        (uint112 reserve0, uint112 reserve1,) = getReserves();

        if (amount0Out >= reserve0 || amount1Out >= reserve1) {
            revert GTPair__InsufficientPoolLiquidity();
        }

        uint256 balance0;
        uint256 balance1;

        address _token0 = s_token0;
        address _token1 = s_token1;

        if (to == _token0 || to == _token1) {
            revert GTPair__InvalidTo();
        }

        // If the amount0Out (i_token0) is more than zero, meaning this is the token and quantity they want, transfer.
        if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out);
        // If the amount1Out (i_token1) is more than zero, meaning this is the token and quantity they want, transfer.
        if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // For example, reserve0 = 100 and amount0Out = 10
        // Is our new i_token0 balance > (90)? — 90 would be our balance from tokens output with no input.
        // If it is, an amount of tokens has been input.
        // Let's say our new balance is 96. 96 - (100 - 10 (90)) = 6 tokens input.
        uint256 amount0In = balance0 > (reserve0 - amount0Out) ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > (reserve1 - amount1Out) ? balance1 - (reserve1 - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) {
            revert GTPair__InsufficientInputAmount();
        }

        uint256 balance0Adjusted = (balance0 * FEE_PRECISION) - (amount0In * FEE);
        uint256 balance1Adjusted = (balance1 * FEE_PRECISION) - (amount1In * FEE);

        // We scaled balanceAdjusted by 1000, and here multiplied them together. We need to the scale the product of reserve0 and reserve0 (both unscaled) by 1,000,000.
        if ((balance0Adjusted * balance1Adjusted) < (uint256(reserve0) * reserve1) * (FEE_PRECISION ** 2)) {
            revert GTPair__InvalidK(
                balance0Adjusted * balance1Adjusted, (uint256(reserve0) * reserve1) * (FEE_PRECISION ** 2)
            );
        }
        _updateReserves(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @notice Mints address LP tokens. This function is called by the Router, with tokens transfered with the call.
     * @param to The address we are minting LP tokens to.
     * @return liquidity The number of LP tokens we minted.
     */
    function mint(address to) external returns (uint256 liquidity) {
        // Tokens have been transferred in from the Router.
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        uint256 balance0 = IERC20(s_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(s_token1).balanceOf(address(this));

        // To calculate the amount of tokens sent in, subtract the outdated reserves from the new token balances.
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        // The current total supply of LP tokens.
        uint256 _totalSupply = totalSupply();
        // If it's the first deposit...
        if (_totalSupply == 0) {
            // Mint the geometric mean of the amounts.
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            // Mint address(0) the MINIMUM_LIQUIDITY, to ensure the first depositor does not have the total supply.
            _mint(i_burnAddress, MINIMUM_LIQUIDITY);
        } else {
            // Check to see user deposited correct ratio of tokens.
            // Number of LP tokens to mint is the minimum of these two values:
            liquidity = Math.min((amount0 * _totalSupply) / reserve0, (amount1 * _totalSupply) / reserve1);
            // If a user only deposits one token, they will be minted 0 LP tokens, as it will be the minimum values of these two values.
            // If a user deposits more than required for one token, they will only be minted the LP tokens which correspond with the correct token deposit amount, and extra tokens will be considered a donation to the pool.
        }
        if (liquidity == 0) {
            revert GTPair__InsufficientLiquidityMinted();
        }
        _mint(to, liquidity);
        _updateReserves(balance0, balance1);
        // @note Look at fee
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Burns LP tokens. This function is called by the Router, which sends LP tokens with the call.
     * @param to The address we are sending the pool tokens to after burn.
     * @return amount0 The amount of i_token0 we send the user.
     * @return amount1 The amount of i_token1 we send the user.
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        // (uint112 reserve0, uint112 reserve1,) = getReserves();
        address token0 = s_token0;
        address token1 = s_token1;
        uint256 balance0 = IERC20(s_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(s_token1).balanceOf(address(this));

        // Gets the amount of tokens sent in with the transaction.
        // As the pool originally has no tokens, any increase will be the tokens transerred via this transaction.
        uint256 liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) {
            revert GTPair__InsufficientLiquidityBurned();
        }
        // Burn the tokens that were sent to this address, aka our LP token balance.
        _burn(address(this), liquidity);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _updateReserves(balance0, balance1);
        // @note Look at fee
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @notice Fetches our reserve and time last updated variables.
     * @return s_reserve0 The token0 reserve.
     * @return s_reserve1 The token1 reserve.
     * @return s_blockTimestampLast The last time our reserves were updated.
     */
    function getReserves() public view returns (uint112, uint112, uint32) {
        return (s_reserve0, s_reserve1, s_blockTimestampLast);
    }

    /**
     * @notice Updates our s_reserve0 and s_reserve1 storage variables. It is called when there has been a change to our reserves, such as a swap or a deposit of liquidity.
     * @param balance0 The updated token0 balance.
     * @param balance1 The updated token1 balance.
     */
    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        s_reserve0 = uint112(balance0);
        s_reserve1 = uint112(balance1);
        s_blockTimestampLast = uint32(block.timestamp);
        emit Sync(s_reserve0, s_reserve1);
    }

    function getTokens() external view returns (address, address) {
        return (s_token0, s_token1);
    }
}
