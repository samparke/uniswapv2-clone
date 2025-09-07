// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGTFactory} from "./interfaces/IGTFactory.sol";
import {GTLibrary} from "../src/libraries/GTLibrary.sol";
import {IGTPair} from "./interfaces/IGTPair.sol";
import {console2} from "forge-std/Test.sol";
import {IGTRouter} from "./interfaces/IGTRouter.sol";

contract GTRouter is IGTRouter {
    using SafeERC20 for IERC20;

    error GTRouter__DeadlinePassed();
    error GTRouter__TokensCannotBeTheSame();
    error GTRouter__UnknownTokens();
    error GTRouter__SlippageTooHigh();
    error GTRouter__InsufficientBAmount();
    error GTRouter__InsufficientAAmount();
    error GTRouter__InsufficientAmountOut();
    error GTRouter__ExcessiveInputAmount();

    address public immutable override i_factory;

    uint256 public constant FEE = 3; // 0.3%
    uint256 public constant FEE_PRECISION = 1000;

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) {
            revert GTRouter__DeadlinePassed();
        }
        _;
    }

    constructor(address factory) {
        i_factory = factory;
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
        if (IGTFactory(i_factory).getPair(tokenA, tokenB) == address(0)) {
            IGTFactory(i_factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = GTLibrary.getReserves(i_factory, tokenA, tokenB);

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
                console2.log("amountAMin", amountAMin);
                console2.log("amountAOptimal", amountAOptimal);
                console2.log("amountADesired", amountADesired);
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
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = GTLibrary.pairFor(i_factory, tokenA, tokenB);
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
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = GTLibrary.pairFor(i_factory, tokenA, tokenB);
        // Transfers LP tokens to pair address.
        IERC20(pair).safeTransferFrom(msg.sender, address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = IGTPair(pair).burn(to);
        (address token0,) = GTLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountAMin > amountA) {
            revert GTRouter__InsufficientAAmount();
        }
        if (amountBMin > amountB) {
            revert GTRouter__InsufficientBAmount();
        }
    }

    /**
     *
     * @param amounts The amountsOut for each token in the path, calculated from the prior (swap exact tokens / swap tokens for exact) function
     * @param path The sequence of token hops.
     * @param _to The recipient of the token swap.
     */
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = GTLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            // token0 is entering the pool, hence amount out = 0. E.g. 1. WETH (0) USDC (2000), 2. USDC(0) DAI(2000)
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            // If the current hop is not the second to last in the path, send tokens to the next pool in the sequence.
            // If it is, we want to send the output tokens to the user who was to 'to' address in the swap initiation.
            address to = i < path.length - 2 ? GTLibrary.pairFor(i_factory, output, path[i + 2]) : _to;
            IGTPair(GTLibrary.pairFor(i_factory, input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    /**
     *
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The users minimum acceptable amount of tokens received from the amountIn.
     * @param path The sequence of token hops to get from the token of amountIn to the token of amountOut. This is determined off-chain.
     * @param to The recipient of the token swap.
     * @param deadline The duration of time the user is willing to wait for a token swap.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        // For the amountIn, get each amount out for each token in the path.
        amounts = getAmountsOut(amountIn, path);
        // Revert if the amountsOut is less than the acceptable amount for the user.
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert GTRouter__InsufficientAmountOut();
        }
        // If the amountsOut is above the minimum accepted by the user, initiate the swap by transferring tokens to pool.
        IERC20(path[0]).safeTransferFrom(msg.sender, GTLibrary.pairFor(i_factory, path[0], path[1]), amountIn);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert GTRouter__ExcessiveInputAmount();
        }
        IERC20(path[0]).safeTransferFrom(msg.sender, GTLibrary.pairFor(i_factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /*//////////////////////////////////////////////////////////////
                           LIBRARY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return (GTLibrary.getAmountIn(amountOut, reserveIn, reserveOut));
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return (GTLibrary.getAmountOut(amountIn, reserveIn, reserveOut));
    }

    function getAmountsIn(uint256 amountsOut, address[] calldata path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return (GTLibrary.getAmountsIn(i_factory, amountsOut, path));
    }

    function getAmountsOut(uint256 amountsIn, address[] calldata path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return (GTLibrary.getAmountsOut(i_factory, amountsIn, path));
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return (GTLibrary.quote(amountA, reserveA, reserveB));
    }
}
