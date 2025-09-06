// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IGTPair} from "../interfaces/IGTPair.sol";
import {GTPair} from "../GTPair.sol";

library GTLibrary {
    error GTLibrary__IdenticalTokens();
    error GTLibrary__TokenCannotBeZeroAddress();
    error GTLibrary__InsufficientInputAmount();
    error GTLibrary__InsufficientLiquidity();
    error GTLibrary__InvalidPath();
    error GTLibrary__InsufficientAmount();

    bytes32 internal constant INIT_CODE_HASH = keccak256(type(GTPair).creationCode);
    uint256 public constant FEE = 3;
    uint256 public constant FEE_PRECISION = 1000;

    /**
     * @notice Fetches the reserve from a pool, corresponding with tokenA and tokenB
     * @param factory The factory contract
     * @param tokenA The first token input
     * @param tokenB The second token input
     * @return reserveA The token reserve of token0
     * @return reserveB The token reserve of token1
     */
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IGTPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @notice Canonical ordering of tokens, where token0 is always the smaller address between tokenA and tokenB
     * @param tokenA The first token input
     * @param tokenB The second token input
     * @return token0 The ordered token0
     * @return token1  The ordered token1
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) {
            revert GTLibrary__IdenticalTokens();
        }
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert GTLibrary__TokenCannotBeZeroAddress();
        }
    }

    /**
     * @notice Constructs the CREATE2 address for a pair of tokens
     * @param factory The factory contract — the deployer.
     * @param tokenA The first token input.
     * @param tokenB The second token input.
     * @return pair The CREATE2 address for the pair
     */
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        // CREATE2 address is created by: keccak256("0xFF", deployer, salt, keccak256(bytecode))
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), INIT_CODE_HASH)
                    )
                )
            )
        );
    }

    /**
     * @notice  Given an amount of tokenA, returns the value in relation to the amount of token B.
     * For example, 1 WETH may be equal to 2,000 USDC. Not necessarily the price, just it's value relative to the other token.
     * @param amountA The amount of the tokenA being valued.
     * @param reserveA The reserves of tokenA.
     * @param reserveB The reserves of tokenB.
     * @return amountB The amount of tokenB equivalent to amountA at the current ratio.
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA < 0) {
            revert GTLibrary__InsufficientAmount();
        }
        if (reserveA == 0 || reserveB == 0) {
            revert GTLibrary__InsufficientLiquidity();
        }
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @notice Calculates the amount out for each token in the path, based on the amount of a token being input.
     * For example, if the path is WETH, USDC and DAI, we can predict the amount of DAI from the WETH input.
     * @dev This function does not provide the optimal paths. It simply, given a path (which would have been constructed off-chain),
     * calculates the amount out for the subsequent token in the path, based on the first token input.
     * @param factory The factory address
     * @param amountIn The amount of the first token in the sequence being input.
     * @param path The sequence of tokens in the pairs. For example, path[0] = WETH, path[1] = USDC and path[2] = DAI.
     */
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert GTLibrary__InvalidPath();
        }

        amounts = new uint256[](path.length);
        // The amount of the first token input.
        amounts[0] = amountIn;
        // Iterates over each token.
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);

            // E.g.
            // Our first iteration: get the pair pool reserves from getReserves(factory, WETH, USDC),
            // and then calculate the amount of USDC we will receive from the WETH input.

            // Our second iteration: get the pair pool reserves from getReserves(factory, USDC, DAI),
            // and then calculate the amount of DAI we will receive from the USDC input (based on our previous calculated output).
        }
    }

    /**
     * @notice Calculates the required amount of tokens input, for the desired amount of output tokens at end of path.
     * @param factory The factory address.
     * @param amountOut The desired amount out of the final token in the path.
     * @param path The sequence of tokens in the path.
     */
    function getAmountsIn(address factory, uint256 amountOut, address[] calldata path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert GTLibrary__InvalidPath();
        }

        amounts = new uint256[](path.length);
        // The final token in the path = amountOut.
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
            // E.g.
            // Our first iteration: get reserves from getReserves(factory, USDC, DAI),
            // and then calculate the amount USDC required to get desired DAI.

            // Our second iteraton: get reserves from getReserves(factory, WETH, USDC),
            // and then calcukate the amount of WETH required to get desired USDC (which is required to get amountOut DAI).
        }
    }

    /**
     * @notice Calculates the amount of tokens that will leave the pool, from the amount being entered.
     * @param amountIn The amount of tokens entering.
     * @param reserveIn The reserve of the tokens entering.
     * @param reserveOut The reserve of the tokens exiting.
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (
            // moreThanZero(amountIn)
            uint256 amountOut
        )
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTLibrary__InsufficientLiquidity();
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
     * @notice Calculates the amount of tokens that must enter the pool, from the amount leaving the pool.
     * @param amountOut The amount of the token leaving the pool.
     * @param reserveIn The reserve of the token entering the pool.
     * @param reserveOut The reserve of the token leaving the pool.
     * @return amountIn The amount of tokens that must enter the pool, from the amount leaving the pool.
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTLibrary__InsufficientLiquidity();
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
