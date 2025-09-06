// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IGTPair} from "../interfaces/IGTPair.sol";
import {GTPair} from "../GTPair.sol";

library GTLibrary {
    error GTLibrary__IdenticalTokens();
    error GTLibrary__TokenCannotBeZeroAddress();
    error GTLibrary__InsufficientInputAmount();
    error GTLibrary__InsufficientLiquidity();

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
     * @notice Quotes the amount a user would receive from a swap, if they input an an amount in at the current ratio, based on reserves of the token in and token out.
     * @param amountIn The amount of the token the user is swapping in.
     * @param reserveIn The reserves of the token the user is swapping in.
     * @param reserveOut The reserves of the token the user is swapping out.
     * @return amountOut The amount of the token which would come out of the pool and be given to the user.
     */
    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert GTLibrary__InsufficientInputAmount();
        }
        if (reserveIn == 0 || reserveOut == 0) {
            revert GTLibrary__InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * (FEE_PRECISION - FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_PRECISION) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
