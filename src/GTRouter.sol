// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {GTPair} from "./GTPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGTFactory} from "./interfaces/IGTFactory.sol";
import {GTLibrary} from "../src/libraries/GTLibrary.sol";
import {IGTPair} from "./interfaces/IGTPair.sol";

contract GTRouter {
    using SafeERC20 for IERC20;

    error GTRouter__DeadlinePassed();
    error GTRouter__TokensCannotBeTheSame();
    error GTRouter__UnknownTokens();
    error GTRouter__SlippageTooHigh();
    error GTRouter__InsufficientpairLiquidity();
    error GTRouter__InsufficientBAmount();
    error GTRouter__InsufficientAAmount();

    address public immutable factory;

    uint256 public constant FEE = 3; // 0.3%
    uint256 public constant FEE_PRECISION = 1000;

    modifier ensure(uint256 deadline) {
        if (deadline >= block.timestamp) {
            revert GTRouter__DeadlinePassed();
        }
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                             ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function called by 'addLiquidity', which calculates the amount of liquidity to add.
     * @param tokenA Token A of the pair
     * @param tokenB Token B of the pair
     * @param amountADesired The amount of token A the user wants to deposit.
     * @param amountBDesired The amount of token B the user wants to deposit.
     * @param amountAMin The minimum amount of token A they are willing to accept to deposit, compared to the desired amount.
     * @param amountBMin The minimum amount of token B they are willing to accept to deposit, compared to the desired amount.
     * @return amountA The amount of token A which will be deposited from the user.
     * @return amountB The amount of token B which will be deposited from the user.
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // If the pair doesn't exist, create it
        if (IGTFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IGTFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = GTLibrary.getReserves(factory, tokenA, tokenB);

        // If there are currently no reserves, amountA and amountB are the desired amounts by the user, meaning amountADesired and amountBDesired will be the amount deposited.
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // If there are reserves, calculate the optimal amount of B to deposit for the amount of token A the user wants to deposit.
            uint256 amountBOptimal = GTLibrary.quote(amountADesired, reserveA, reserveB);
            // If the amountBDesired is greater or equal to the amountBOptimal...
            if (amountBOptimal <= amountBDesired) {
                // But amountBMin is greater than the optimal amount, revert. The optimal did not meet the users standards.
                if (amountBMin > amountBOptimal) {
                    revert GTRouter__InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // If amountBOptimal needed to match the pools ratio is greater than the users amountBDesired, assess whether the reverse is possible.
                uint256 amountAOptimal = GTLibrary.quote(amountBDesired, reserveB, reserveA);
                // The amount of token A the user wants to deposit must be greater or equal to the required amount.
                assert(amountAOptimal <= amountADesired);
                // If it does, but its less than the minimum acceptable amount from the user, revert.
                if (amountAMin > amountAOptimal) {
                    revert GTRouter__InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
     *
     * @param tokenA Token A of the pair
     * @param tokenB Token B of the pair
     * @param amountADesired The amount of token A the user wants to deposit.
     * @param amountBDesired The amount of token B the user wants to deposit.
     * @param amountAMin The minimum amount of token A they are willing to accept to deposit, compared to the desired amount.
     * @param amountBMin The minimum amount of token B they are willing to accept to deposit, compared to the desired amount.
     * @param to The address we want to mint LP tokens to
     * @param deadline The amount of time the user will wait to deposit liquidity. The ratio could be different in, say, 10 minutes time.
     * @return amountA The amount of token A which will be deposited from the user.
     * @return amountB The amount of token B which will be deposited from the user.
     * @return liquidity The amount of LP tokens to mint to the 'to' address
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = GTLibrary.pairFor(factory, tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IGTPair(pair).mint(to);
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Removes liquidity from the pool by burning LP tokens, and transferring token A and token B to the 'to' address.
     * @param tokenA Token A of the pair
     * @param tokenB Token B of the pair
     * @param liquidity The amount of LP tokens the user wishes to burn.
     * @param amountAMin The minimum amount of tokenA the user will accept receiving.
     * @param amountBMin The minimum amount of tokenB the user will accept receiving.
     * @param to The address the pair contract will send tokenA and tokenB to after burning LP tokens.
     * @param deadline The amount of time the user is willing to wait to remove liquidty.
     * @return amountA The amount of tokenA which will be returned.
     * @return amountB The amount of tokenB which will be returned.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = GTLibrary.pairFor(factory, tokenA, tokenB);
        // Transfers LP tokens to pair address.
        IERC20(pair).safeTransferFrom(msg.sender, address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = IGTPair(pair).burn(to);
        (address token0,) = GTLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = token0 == tokenA ? (amount0, amount1) : (amount1, amount0);
        if (amountAMin > amountA) {
            revert GTRouter__InsufficientAAmount();
        }
        if (amountBMin > amountB) {
            revert GTRouter__InsufficientBAmount();
        }
    }

    // function _swap() internal {}

    // function swapExactTokensForTokens(
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn,
    //     uint256 amountOutMin,
    //     address to,
    //     uint256 deadline
    // ) external ensure(deadline) {
    //     if (tokenIn == tokenOut) {
    //         revert GTRouter__TokensCannotBeTheSame();
    //     }
    //     if (!((tokenIn == i_token0 && tokenOut == i_token1) || (tokenIn == i_token1 && tokenOut == i_token0))) {
    //         revert GTRouter__UnknownTokens();
    //     }
    //     (uint256 _reserve0, uint256 _reserve1,) = pair.getReserves();
    //     bool tokenInIsTokenZero = tokenIn == i_token0;
    //     // If tokenIn is token0, reserveIn = reserve0. However, if tokenIn is token1, reserveIn is reserve1.
    //     uint256 reserveIn = tokenInIsTokenZero ? _reserve0 : _reserve1;
    //     // If tokenIn is token0, reserveOut = reserve1. However, if tokenIn is token1, reserveOut is reserve0.
    //     uint256 reserveOut = tokenInIsTokenZero ? _reserve1 : _reserve0;

    //     uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    //     if (amountOut < amountOutMin) {
    //         revert GTRouter__SlippageTooHigh();
    //     }

    //     // @note CHANGE THIS TO ROUTER IMPLEMENTATION. TOKENS SENT IN WITH TRANSACTION.
    //     IERC20(tokenIn).safeTransferFrom(msg.sender, address(pair), amountIn);
    //     // IERC20(tokenOut).safeTransfer(to, amountOut);
    //     _swap();
    // }

    /**
     * @notice Calculates the amount of tokens leaving the pair from the amount that came in.
     * @param amountIn The amount of the token entering the pair.
     * @param reserveIn The reserve of the token entering the pair.
     * @param reserveOut The reserve of the token leaving the pair.
     * @return amountOut The amount of tokens leaving the pair.
     */
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (
            // moreThanZero(amountIn)
            uint256 amountOut
        )
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTRouter__InsufficientpairLiquidity();
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

    /**
     * @notice Calculates the amount of tokens that must enter the pair from the desired amount leaving the pair.
     * @param amountOut The desired amount of the token leaving the pair.
     * @param reserveIn The reserve of the token entering the pair.
     * @param reserveOut The reserve of the token leaving the pair.
     * @return amountIn The amount of tokens that must enter the pair for the desired amount leaving the pair.
     */
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (
            // moreThanZero(amountOut)
            uint256 amountIn
        )
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTRouter__InsufficientpairLiquidity();
        }
        // Use the same scenario: amountOut = 9, reserveIn = 100, reserveOut = 100

        // numerator = 100 * 9 * 1000 = 900,000
        uint256 numerator = reserveIn * amountOut * FEE_PRECISION;
        // denominator = (100 - 9) * 997 = 90,727
        uint256 denominator = (reserveOut - amountOut) * (FEE_PRECISION - FEE);
        // amoountIn = (900,000 + 90,727 - 1) / 90,727 = 10.91, rounded down to 10. 10 tokens in for 9 tokens out.
        amountIn = (numerator + denominator - 1) / denominator;
    }
}
