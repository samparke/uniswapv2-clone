// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {GTFactory} from "./GTFactory.sol";
import {IGTFactory} from "../src/interfaces/IGTFactory.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {LP} from "./LP.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GTPool is LP {
    using SafeERC20 for IERC20;

    error GTPool__InsufficientOutputAmount();
    error GTPool__InsufficientPoolLiquidity();
    error GTPool__ZeroAddressError();
    error GTPool__CannotOutputTwoTokens();
    error GTPool__CannotBeZeroAddress();
    error GTPool__MoreThanZero();
    error GTPool__TokensCannotBeTheSame();
    error GTPool__SlippageTooHigh();
    error GTPool__DeadlinePassed();
    error GTPool__UnknownTokens();
    error GTPool__InsufficientLiquidityMinted();

    address public immutable i_token0;
    address public immutable i_token1;

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

    modifier zeroAddress(address inputAddress) {
        if (inputAddress == address(0)) {
            revert GTPool__CannotBeZeroAddress();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) override {
        if (amount == 0) {
            revert GTPool__MoreThanZero();
        }
        _;
    }

    constructor(address token0, address token1, address factory) {
        i_token0 = token0;
        i_token1 = token1;
        i_factory = factory;
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external zeroAddress(tokenIn) zeroAddress(tokenOut) {
        if (block.timestamp > deadline) {
            revert GTPool__DeadlinePassed();
        }
        if (tokenIn == tokenOut) {
            revert GTPool__TokensCannotBeTheSame();
        }
        if (!((tokenIn == i_token0 && tokenOut == i_token1) || (tokenIn == i_token1 && tokenOut == i_token0))) {
            revert GTPool__UnknownTokens();
        }
        (uint256 _reserve0, uint256 _reserve1,) = getReserves();
        bool tokenInIsTokenZero = tokenIn == i_token0;
        // If tokenIn is token0, reserveIn = reserve0. However, if tokenIn is token1, reserveIn is reserve1.
        uint256 reserveIn = tokenInIsTokenZero ? _reserve0 : _reserve1;
        // If tokenIn is token0, reserveOut = reserve1. However, if tokenIn is token1, reserveOut is reserve0.
        uint256 reserveOut = tokenInIsTokenZero ? _reserve1 : _reserve0;

        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < amountOutMin) {
            revert GTPool__SlippageTooHigh();
        }

        // @note CHANGE THIS TO ROUTER IMPLEMENTATION. TOKENS SENT IN WITH TRANSACTION.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(to, amountOut);

        uint256 balance0 = IERC20(i_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(i_token1).balanceOf(address(this));

        _updateReserves(balance0, balance1);
    }

    function swapTokensForExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        uint256 deadline
    ) external {}

    function mint(address to) external returns (uint256 liquidity) {
        // Tokens have been transferred in from the Router.
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        uint256 balance0 = IERC20(i_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(i_token1).balanceOf(address(this));

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
            revert GTPool__InsufficientLiquidityMinted();
        }
        _mint(to, liquidity);
        _updateReserves(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (s_reserve0, s_reserve1, s_blockTimestampLast);
    }

    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        s_reserve0 = uint112(balance0);
        s_reserve1 = uint112(balance1);
        s_blockTimestampLast = uint32(block.timestamp);
        emit Sync(s_reserve0, s_reserve1);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        moreThanZero(amountIn)
        returns (uint256 amountOut)
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTPool__InsufficientPoolLiquidity();
        }
        // To calculate amount out with fee:
        // dy = dx * (1 - FEE) * y / x + dx * (1 - FEE)

        // We must scale these values to account for no decimals in Solidity.
        // Let's say amountIn = 10, reserveIn = 100 and reserveOut = 100

        // amountInWithFee = 10 * 997 = 9,970
        uint256 amountInWithFee = amountIn * (FEE_PRECISION - FEE);
        // numerator = 9,970 * 100 = 997,000
        uint256 numerator = amountInWithFee * reserveOut;
        // denominator = (100 * 1000) + 9,970
        // We must scale up reserves by 1000, as we scaled up the fee.
        //             = 100,000 + 9,970
        //             = 109,970
        uint256 denominator = reserveIn * FEE_PRECISION + amountInWithFee;
        // amountOut = 997,000 / 109,970
        //           = 9.06 (rounded down to 9)
        amountOut = numerator / denominator;

        // This is equivalent to our original formula: dy = dx * (1 - FEE) * y / x + dx * (1 - FEE)
        // dy = 10 * 0.997 * 100 (997) / 100 + 10 * 0.997 (109.97)
        // dy = 997 / 109.97
        // dy = 9.06
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        moreThanZero(amountOut)
        returns (uint256 amountIn)
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTPool__InsufficientPoolLiquidity();
        }
        // Use the same scenario: amountOut = 9, reserveIn = 100, reserveOut = 100

        // numerator = 100 * 9 * 1000 = 900,000
        uint256 numerator = reserveIn * amountOut * FEE_PRECISION;
        // denominator = (100 - 9) * 997 = 90,727
        uint256 denominator = (reserveOut - amountOut) * (FEE_PRECISION - FEE);
        // amoountIn = (900,000 + 90,727 - 1) / 90,727 = 10.91, rounded down to 10. 10 tokens in for 9 tokens out.
        amountIn = (numerator + denominator - 1) / denominator;
    }

    function setGtToken() external {}
}
