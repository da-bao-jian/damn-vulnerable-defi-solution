![](cover.png)

**A set of challenges to hack implementations of DeFi in Ethereum.**

Featuring flash loans, price oracles, governance, NFTs, lending pools, smart contract wallets, timelocks, and more!

Created by [@tinchoabbate](https://twitter.com/tinchoabbate)


## Disclaimer

All Solidity code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.


## Solution

1. Unstoppable

There's a lending pool offering flash loan, and a player's goal is to stop the pool. There are two contracts: `UnstoppableLender` and `ReceiverUnstoppable`. `Unstoppable` has two function: 1) `depositTokens()` to allow users increase the `poolBalance`; 2) `flashLoan()` to allow users execute flashloans. `ReceiverUnstoppable` provides users functions needed to execute flashloans. 

Upon reading the prompt, I thought about three possible scenarios where the contract could be exploited: 1) `depositTokens()` likely interacts with external contracts via ERC20's `transfer()` or `transferFrom()`, so a re-entrancy attack might be possible to drain the contract's entire liquidity; 2) `flashLoan()` functions often use `msg.sender` contract's function to return the loan borrowed, therefore its implementation could cause problem; 3) `flashLoan()` function normally compares before and after contract balances to make sure correct amount of loan was returned, thus if token at issue is a deflationary token, there could potentially be an issue? 

After reading the contracts, first two guesses are obvsiouly wrong, because first, `depositTokens` uses a reentrancy guard, and second `receiveTokens()`'s implementation is simple and works exactly how it should work. My last guess might be wrong as well since there's no indication `DVT` token is deflationary and logic inside of require statements look fine to me. But, wait, 
```
assert(poolBalance == balanceBefore);
```
looks suspicious. `poolBalance` is a state variable only modified inside of `depositTokens()`, but `balanceBefore` is a dynamic value that tracks the contract's token balance. If I can increase/decrease the contract's balance, I should be able to put `poolBalance` out of sync with `balanceBefore`. Conviniently, ERC20 token has `transfer()` method that I increase the contract balance while keeping `poolBalance` unchanged. 

Below is the code:
```
// I'm cheap so I only gave it 1 token, but it works :)
await this.token.transfer(this.pool.address, 1, );
```

2. Naive Receiver

There's a lending pool offering expensive flashloan, and there's another contract capable of interacting with the flashloan pool. The pool has 1000 ETH in balance, and the other contract has 10 ETH. The goal is to drain the 10ETH in the contract and transfer them to the pool. 

By looking at the pool contract, I realized that the fee, which equals 1 ETH, is incredibly high. The brute force way to solve this challenge would be invoking the `flashloan` function 10 times. However, the challenge did encourage stealing the fund in one single transaction, therefore there must be better ways. 

To achieve the same goal, I can deploy a attacker contract that invoke the `flashLoan` contract 10 times with victim's address as the argument. Then, in the test, I could just deploy this contract and invoke the function that interacts with the flashloan contract. 
