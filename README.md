![](cover.png)

[Damn Vulnerable Defi](damnvulnerabledefi.xyz/)

**A set of challenges to hack implementations of DeFi in Ethereum.**

Featuring flash loans, price oracles, governance, NFTs, lending pools, smart contract wallets, timelocks, and more!

Created by [@tinchoabbate](https://twitter.com/tinchoabbate)


## Disclaimer

All Solidity code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.


## Solution

### 1. Unstoppable

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

![naive receiver](https://github.com/da-bao-jian/damn-vulnerable-defi-solution/blob/master/pic/Screenshot%20from%202021-12-01%2001-31-34.png)

3. Truster

This challenge asks the challenger to steal all of the balance from a lending pool that offers flashloans. The contract is quite simple as it only has one function `flashLoan`. The `flashLoan` is a stereotypical flashloan function that compares balance before and after, and invokes another contract's function. The intersting part is the way how it interacts with other contracts. It uses OpenZeppelin's `functionCall` method, which is a wrapper for Solidity's low level `call` method. This opens the door for it to interact with any arbitrary functions on any contracts. There are two ways to solve this challenge: 1) deploy a attacker contract that invokes `flashLoan` function with malicious logic or 2) fill in the `calldata` from the test case. I'll do both here. 

The full implementation is [here](https://github.com/da-bao-jian/damn-vulnerable-defi-solution/blob/master/contracts/truster/attacker.sol). 


4. Side Entrance

Again, this challenge presents a stereotypical flash loan contract that checks balances before and after the loan. However, what's unique about this contract is that the lending contract it interacts with has to implement `IFlashLoanEtherReceiver` interface. `IFlashLoanEtherReceiver` interface only has one function named `execute()`. It is up to us how we want to implement it. This opens the door to endless posibilities. For this particular challenge, we want to steal all of the fund on the `SideEntranceLenderPool` contract. By a close examination, I found that `deposit` and `withdraw` methods can be used together to create fake balance out of thin air, in other words, one can increase one's balance using `deposit` method without necessarily depositing anyting and call `withdraw` method later to withdraw funds that was never deposited in the first place. To achieve this, I wrote the `execute()` method to call the `deposit` method using the `value` provided in the `flashLoan()` method. Since I'm not taking a loan out of the `SideEntranceLenderPool` but only use it to call the `deposit()` method, I really don't need to return the loan like one normally would. After that, simply withdraw the fund to our own account. 

DON'T FORGET TO INCLUDE A FALLBACK/RECEIVER FUNCTION!!! 

I spent almost half an hour to debug what went wrong and turned out that I didn't have a receiver function in my attacker contract to receive the transfer. 

The full implementation is [here](https://github.com/da-bao-jian/damn-vulnerable-defi-solution/blob/master/contracts/side-entrance/attack.sol). 

5. Rewarder

Man, this one is messy...

We have four contracts in this challenge, but only two really matter for solving task at hand, namely `TheRewardPool` and `FlashLoanerPool`. We have a reward pool for distributing the reward tokens to participants who firstly desposited the `liquidityToken`. There are four other participants who had engaged in the first round of deposit and had received `rewardToken` on a pro-rata basis for their contributions. The challenge wants the challenger to steal the reward token without participating in the first round of deposit. Since a flash loan contract is provided, we can definitely take advantage of it. 

Below is my thought process:
- Since I want to receive reward token, I need to find the function that's responsible for reward token distribution. 
  - Found it! Its name is `distributeRewards` in `TheRewarderPool`
  ```
    function distributeRewards() public returns (uint256) {
        uint256 rewards = 0;

        if(isNewRewardsRound()) {
            _recordSnapshot();
        }        
        
        uint256 totalDeposits = accToken.totalSupplyAt(lastSnapshotIdForRewards);
        uint256 amountDeposited = accToken.balanceOfAt(msg.sender, lastSnapshotIdForRewards);

        if (amountDeposited > 0 && totalDeposits > 0) {
            rewards = (amountDeposited * 100 * 10 ** 18) / totalDeposits;

            if(rewards > 0 && !_hasRetrievedReward(msg.sender)) {
                rewardToken.mint(msg.sender, rewards);
                lastRewardTimestamps[msg.sender] = block.timestamp;
            }
        }

        return rewards;     
    }
  ```
- Ok, the reward distribution is achieved through `rewardToken.mint(msg.sender, rewards);`, but before that, there are two conditions need to be met:
  - `amountDeposited > 0 && totalDeposits > 0`
  - `rewards > 0 && !_hasRetrievedReward(msg.sender)`
- For first condition, we only need to make sure `amountDeposited > 0` since `totalDeposits` is already larger than 0 because of first two rounds of distributions
  - We can increase `amountDeposited`, aka `accToken.balanceOfAt(msg.sender, lastSnapshotIdForRewards);` by calling the `deposit()` method, which indirectly calls the `distributeRewards()` method. 
    - Where does the deposit come from? We can use flash loan provided by the `TheFlashLoner` contract.  - What about `lastSnapshotIdForRewards`? It would've been updated by `_recordSnapshot()`. And by the time it was updated, we would have already have `accToken` under our name since `accToken` was minted to us before `distributeRewards()` was invoked.
    - Why `_recordSnapshot()` would be invoked? It won't be invoked by itself. We need to hard code it in the test file to force time elapsed to be larger or equal to `REWARDS_ROUND_MIN_DURATION` . 
- For second condition, it would automatically pass if we can mangage to pass the first condition. 
- Now, on to deploy the attack contract. Here are a list of thing it should do:
  - `attack()` function: 
    - get flash loan from `TheFlashLoaner` contract. Here, loan amount should be at least 100 since the test checks the delta between 100 and reward on attacker's balance
    - transfer the stolen reward token back to us;
  - `receiveFlashLoan()` function(indirectly invoked by the `flashLoan` function in `TheFlashLoaner`):
    - approves the `TheRewardPool` contract;
    - calls the `deposit()` function with flash loan received;
    - transfer the `liquidityToken` back to return the flash loan;
    - return the flash loan.
- Lastly, we would need to make sure at 1 days

The full implementation is [here](https://github.com/da-bao-jian/damn-vulnerable-defi-solution/blob/master/contracts/the-rewarder/attacker.sol). 
