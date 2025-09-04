// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {GTPool} from "../src/GTPool.sol";
import {IGTFactory} from "./interfaces/IGTFactory.sol";

contract GTFactory is IGTFactory {
    error GTFactory__PairAlreadyExists();
    error GTFactory__TokensCannotBeTheSame();
    error GTFactory__NotFeeSetter();
    error GTFactory__TokensZeroAddress();

    address public feeAddress; // This is the address which will receive fees (1/6 from liquidity)
    address public feeSetter; // This address can change the feeAddress

    mapping(address => mapping(address => address)) public getPair; // From the pair address, get the tokens in the pair
    address[] public allPairs; // All token pairs created

    event PoolCreated(address indexed tokenA, address indexed tokenB, address pair);

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
    function createPool(address tokenA, address tokenB) external {
        if (tokenA == tokenB) {
            revert GTFactory__TokensCannotBeTheSame();
        }
        if (tokenA == address(0) || tokenB == address(0)) {
            revert GTFactory__TokensZeroAddress();
        }
        GTPool newPair = new GTPool(tokenA, tokenB, address(this));

        // We create two mappings, each with the different orders so that it does not matter which order token a user inputs
        getPair[tokenA][tokenB] = address(newPair);
        getPair[tokenB][tokenA] = address(newPair);
        allPairs.push(address(newPair));
        emit PoolCreated(tokenA, tokenB, address(newPair));
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
