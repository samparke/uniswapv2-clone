// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LP} from "./LP.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGTFactory} from "./interfaces/IGTFactory.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";

contract GTPair is LP, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

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
    error GTPair__Overflow();

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

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

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
        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @notice Mints address LP tokens. This function is called by the Router, with tokens transfered with the call.
     * @param to The address we are minting LP tokens to.
     * @return liquidity The number of LP tokens we minted.
     */
    function mint(address to) external returns (uint256 liquidity) {
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        uint256 balance0 = IERC20(s_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(s_token1).balanceOf(address(this));

        // To calculate the amount of tokens sent in, subtract the outdated reserves from the new token balances.
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        bool feeOn = _mintFee(reserve0, reserve1);
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
        _update(balance0, balance1);
        if (feeOn) {
            kLast = (reserve0 * reserve1);
        }
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Burns LP tokens. This function is called by the Router, which sends LP tokens with the call.
     * @param to The address we are sending the pool tokens to after burn.
     * @return amount0 The amount of i_token0 we send the user.
     * @return amount1 The amount of i_token1 we send the user.
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        address token0 = s_token0;
        address token1 = s_token1;
        uint256 balance0 = IERC20(s_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(s_token1).balanceOf(address(this));

        // Gets the amount of tokens sent in with the transaction.
        // As the pool originally has no tokens, any increase will be the tokens transerred via this transaction.
        uint256 liquidity = balanceOf(address(this));
        bool feeOn = _mintFee(reserve0, reserve1);
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

        _update(balance0, balance1);
        if (feeOn) {
            kLast = (reserve0 * reserve1);
        }
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
    function _update(uint256 balance0, uint256 balance1, uint112 reserve0, uint112 reserve1) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert GTPair__Overflow();
        }
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        // @note unsure if this correct. come back to this
        unchecked {
            uint32 timeElapsed = blockTimestamp - s_blockTimestampLast;
        }

        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            price0CumulativeLast += uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
        }

        s_reserve0 = uint112(balance0);
        s_reserve1 = uint112(balance1);
        s_blockTimestampLast = uint32(block.timestamp);
        emit Sync(s_reserve0, s_reserve1);
    }

    /**
     * @notice Mints the feeAddress 1/6 of the proportion increase in k since kLast was updated.
     * @param reserve0 The pre-minted/burned/swapped reserve0
     * @param reserve1 The pre=minted/burned/swapped reserve1
     */
    function _mintFee(uint256 reserve0, uint256 reserve1) private returns (bool feeOn) {
        address feeTo = IGTFactory(i_factory).feeAddress();
        // If feeTo is not address(0), there is an assigned fee address.
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                // The current rootK
                uint256 rootK = Math.sqrt(reserve0 * reserve1);
                // The last rootK
                uint256 rootKLast = Math.sqrt(_kLast);
                // If the current rookK is greater, the pool has grown.
                if (rootK > rootKLast) {
                    // Scale the difference increase by LP standards
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    // 1/6 of the pool growth minted to feeAddress.
                    // Lets say pool doubled (in k terms) from 100 (rootKLast) to 200 )(rootK).
                    // numerator (say 1000 LP tokens supply) = 1000 * (rootK - rootKLast) = 100,000
                    // denominator = 1000 + 100 = 1100
                    // liquidity = 100,000 / 1100 = 90.9 (90) LP tokens

                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) {
                        _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    /**
     * @notice Gets the pair tokens in the pool.
     * @return The first token.
     * @return The second token.
     */
    function getTokens() external view returns (address, address) {
        return (s_token0, s_token1);
    }

    /**
     * @notice Transfers any tokens which are not accounted for in the reserves to the 'to' address. These tokens may have been donations from adding extra liquidity beyond the required ratio amount.
     * @param to The address receiving the tokens.
     */
    function skim(address to) external nonReentrant {
        address token0 = s_token0;
        address token1 = s_token1;

        IERC20(token0).safeTransfer(to, IERC20(token0).balanceOf(address(this)) - s_reserve0);
        IERC20(token1).safeTransfer(to, IERC20(token1).balanceOf(address(this)) - s_reserve1);
    }

    /**
     * @notice Forces the reserves to be updated. As s_reserve0 and s_reserve1 are seperated from the actual reserves (token.balanceOf), reserves can become out of sync. This function syncs them. Without this function, they are only synced through someone calling either swap, mint or burn.
     */
    function sync() external nonReentrant {
        _update(IERC20(s_token0).balanceOf(address(this)), IERC20(s_token1).balanceOf(address(this)));
    }
}
