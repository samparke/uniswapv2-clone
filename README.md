## Uniswap V2 Clone (first draft)

**Architecture:**

- GTFactory.sol
- GTPair.sol
- GTRouter.sol
- LP.sol
- GTLibrary

**GTFactory:**

The factory contract has the role of creating new pairs through the `createPair` function, as well establishing the fee address, and changing the fee setter address. The fee address is the address which receives LP tokens per mint and burn function call. If this is not desired — for reasons such as avoid LP dilution for liquidity providers — it can be assigned as address(0) at contract creation, or instead changed to address(0) via the `setFeeAddress` function.

The `createPair` function takes two tokens, orders them cannonically so that the smallest address is `GTPair::s_token0` and the larger is `GTPair::s_token1` in the pair contract. It creates the pair via CREATE2 contract creation, and calls `GTPair::initialise`, which sets the two token addresses in the pair contract.

**GTPair:**

At its core, the pair contract allows a user to:

- Deposit liquidity and mint LP tokens which represent their share of the pools reserves.
- Burn LP tokens, which transfers the pair tokens back to the liquidity provider, relative the the number of LP tokens they hold and the pools reserves.
- Swap ERC20 tokens.

_A few explanations on variables and functions. See Natspec for additional information:_

The contract stores the reserves in two variables: `s_reserve0` — which is the reserve of `s_token0` — and `s_reserve1` — which is the reserve of `s_token1`. These variables are updated via the `GTPair::_update` function, each time there is a change in the reserves — for example, after a swap.

`GTPair::initialise` is called by the factory when the contract is created. It changes the empty `s_token0` and `s_token1` storage variables to the token address passed through with the factory's call.

`GTPair::swap` is the function behind a swap. The tokens to be swapped in are sent with the transaction via an ERC20 transfer (either through `GTRouter` or a smart contract). The `amountOut0` and `amountOut1` parameters are the quantities of each token desired from the swap. For this current version, which does not have flash loan functionality, one of these parameters will be set to 0. The parameter with a value is the token the user wants to receive from the swap. After conducting some checks, such as whether the pool has sufficient reserves, the function calculates the amount of tokens received, and checks it does not break the invariant (x \* y < k). k grows due to a 0.3% fee per swap. _See the natspec for in-depth explanation._

`GTPair::mint` mints a liquidity provider LP tokens, depending on the numbers of tokens sent with the call. It subtracts the outdated reserves (`s_reserve0` and `s_reserve1`) from the new balances — to determine the number of tokens deposited as liquidity. If this is the first liquidity deposit, ghost shares are minted to a dead address, which avoids the first depositor having every share of the pool — a strategy to prevent inflation attacks. For the first depositor, liquidity is calculated as the square root of K. An example to show why: LP provider A deposits 10 token A and 10 token B, and then LP provider B deposits 10 token A and 10 token B. Liquidity has doubled. However, calculating liquidity without square root K: first deposit (10(x) \* 10(y) = 100 (k)), after the second deposit (20 \* 20 = 400). Liquidity appears to have quadrupled, despite the actual doubling of liquidity. Calculating liquidity as the square root of K: sqrt(10 _ 10) = 10, sqrt(20 _ 20) = 20 — correct liquidity increase. After the first deposit, LP minting is proportional to the reserves, so that first mint serves as an anchor for all future LP mints. If the liquidity provider is not the first, the LP tokens to mint is the minimum this calculation for each token: (the tokens sent in \* the total supply of LP tokens) / the reserve for the token. By selecting the minimum value, it incentivises the liquidity provider to deposit the correct ratio of tokens, as 0 LP will be minted if only one token is deposited, and the smaller value of the two values will be minted if a deposit of one token is higher than necessary. Finally, the `s_reserve0` and `s_reserve1` are updated at the end via the `GTPair::_update` function, to reflect the new reserves after the liquidity provision.

`GTPair::burn` burns a liquidity providers LP tokens sent in with the transaction. Each token to be sent to the _to_ address is calculated by: (the number of LP tokens sent with the transaction to be burned \* token reserve) / total supply of LP tokens. Like the mint function, reserves are updated via the `GTPair::_update` function.

**GTRouter:**

The router provides safer interaction with the pair contract. It provides functionality to add and remove liquidty, swap tokens (allowing a user to define the amount in to transfer, or the amount out they desire from a swap), and call informational function from the `GTLibrary`, such as `GTLibrary::quote`. It contains checks to ensure a user is sending the correct tokens, automates ERC20 token transfers to functions such as `GTPair::swap`, and allows native ETH swaps (by funneling ETH to the WETH9 contract, and then transferring the received WETH into the pair contract when adding/removing liquidity or swapping tokens). _See natspec for details on each function._

**GTLibrary:**

A library which contains useful functions which are often be called within the `GTRouter` contract. Some of these include: `GTLibrary::getAmountIn`, `GTLibrary::getAmountsIn`, `GTLibrary::getAmountOut`, `GTLibrary::getAmountsOut` — which calculate the required input/output of swaps based on the desired input/output and token reserves; The `GTLibrary::pairFor` function which deterministically computes the address of a pair contract using the CREATE2 formula — used frequently in swap functions to transfer tokens to the correct pair addresses. The `GTLibrary::sortTokens` function arranges tokens based on the size of their addresses. This allows us to correctly align reserves to tokens, and frequently used when calling the `GTLibrary::pairFor` function.

**Features to need to be added in next draft:**

- Flash loan capabiltiies
- Invariant tests
- Checking for gas opimisations
- Refinement of natspec and ensuring alingment with the correct naming convensions
- Usage as an oracle
