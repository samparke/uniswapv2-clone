// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {GTPair} from "../src/GTPair.sol";
import {IGTFactory} from "./interfaces/IGTFactory.sol";
import {IGTPair} from "./interfaces/IGTPair.sol";

contract GTFactory is IGTFactory {
    error GTFactory__PairAlreadyExists();
    error GTFactory__TokensCannotBeTheSame();
    error GTFactory__NotFeeSetter();
    error GTFactory__TokensZeroAddress();

    address public feeAddress; // This is the address which will receive fees (1/6 from liquidity)
    address public feeSetter; // This address can change the feeAddress

    mapping(address => mapping(address => address)) public getPair; // From the pair address, get the tokens in the pair
    address[] public allPairs; // All token pairs created

    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256 pairsLength);

    modifier onlyFeeSetter() {
        if (msg.sender != feeSetter) {
            revert GTFactory__NotFeeSetter();
        }
        _;
    }

    constructor(address _feeAddress, address _feeSetter) {
        feeAddress = _feeAddress;
        feeSetter = _feeSetter;
    }

    /**
     * @notice Creates a pool of pair tokenA and tokenB.
     * @param tokenA The first token in the pair.
     * @param tokenB The second tokens in the pair.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) {
            revert GTFactory__TokensCannotBeTheSame();
        }

        // Canonical ordering to avoid the creation of two seperate pools for the same pair.
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // As token0 is the smaller address between tokenA and tokenB, checking token0 covers both cases.
        if (token0 == address(0)) {
            revert GTFactory__TokensZeroAddress();
        }
        if (getPair[token0][token1] != address(0)) {
            revert GTFactory__PairAlreadyExists();
        }

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        GTPair newPair = new GTPair{salt: salt}();
        pair = address(newPair);
        IGTPair(pair).initialise(token0, token1);

        // We create two mappings, each with the different orders so that it does not matter which order token a user inputs
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(address(pair));
        emit PairCreated(token0, token1, address(pair), allPairs.length);
    }

    /**
     * @notice Sets new fee address for fees to be sent to.
     * @param newFeeAddress The new fee address.
     */
    function setFeeAddress(address newFeeAddress) external onlyFeeSetter {
        feeAddress = newFeeAddress;
    }

    /**
     * @notice Sets new fee setter. This can only be executed by the current fee setter.
     * @param newFeeSetter The new fee setter.
     */
    function setFeeSetter(address newFeeSetter) external onlyFeeSetter {
        feeSetter = newFeeSetter;
    }
}
