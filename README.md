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

The full implementation is here. 

6. Selfie

This challenge is somewhat similar to the last one, but therer's one more layer to it. We need to deploy a contract that's called by the flash loan contract to interact with a third contract. 

The challenge has two contracts: `SelfiePool` and `SimpleGovernance`. `SelfiePool` provides flash loan and `SimpleGovernance` provides strerotypical governance token mechanisms. The goal of this challenge is to steal all of the fund on the `SelfiePool` contract. 

A quick search of two contracts should reveal that there's a function called `drainAllFunds()` looks suspicious. Isn't this is exactly what we want? However, it is conditioned by a modifier named `onlyGovernance`, which indicates that it can only be invoked by the `SimpleGovernance` contract. Then, the next step is to figure out how to take control of the governance contract. 

Function `executeAction()` provides a low level call through OpenZeppelin's `functionCallWithValue()` medthod. However, the calldata portion of the method can only provided by function `queueAction()`. Therefore, we need to figure out how to invoke `queueAction()`. Good new is to invoke `queueAction()`, one only needs to pass `_hasEnoughVote()` method, which checks an account's token balance agaisnt half of total supply. How are we going to get prefill the account with enough token? FlashLoan! 

To solve this challenge, we first write the `receiveTokens()` method that will be called by the `flashLoan()` method. In `receiveTokens()`, we do three things:
- invoke the DamnVulnerableTokenSnapshot's `snapshot()` method to give `lastSnapshot` a value;
- then, we call the `queueAction` method to fill calldata, which encodes a function call to `drainAllFunds()`
- return the flashloan. 

Eventually, we can invoke the `executeAction()` to drain the fund. 

The full implementation is here. 

7. Compromised

This was a hard one for me as I've don't have any formal conputer science trainings. Took me quite a while to figure out what those numbers were. 

The challenge provides an exchange that one can use to buy/sell NFT, and NFT's price is queried from an oracle contract. The goal is to steal all of the funds on the exchange contract. Additionally, the chellenge also provides two hex data without explicit explanations. 

Since the goal is to steal funds, let's see how exchange contract interacts with others. It has two functions: `buyOne()` and `sellOne()`. `buyOne()` queries the oracle contract to receive the  buying price, and `sellOne()` does the same for getting the selling price. Other than the oracle contract, both also interact with `msg.sender` to receive and transfer funds. My guess is the solution should use one of them to siphon off the fund. `sellOne()` seems more fitting to our purpose as it transfer out the funds on the contract to the `msg.sender`. Dive deeper, I realized that the value sent to `msg.sender` is determined by the `currentPriceinWei` variable, which is the price feed queried from the oracle contract. Therefore, to change the value of `currentPriceinWei`, I need to manipulate the oracle contract. 

Looking at the oracle contract's functions that the exchange contract interacts with, function `getMedianPrice()` directly affect the value of `currentPriceinWei`. Flattening out the `getMedianPrice())`, it serves to provide the median value of three existing NFT prices. In the process, it utilizes the value provided by `pricesBySource[source][symbol]`, which returns the price given a source(address of the `TRUSTED_SOURCE_ROLE`) and a token symbol(in our case, `DVNFT`). This is the value we want! The oracle contract convinient provides a method named `postPrice()` to modify the state of `pricesBySource` . However, `postPrice()` can only be called by any one of the `TRUSTED_SOURCE_ROLE`. In the current challenge, they are the three addresses provided in the test: 
- '0xA73209FB1a42495120166736362A1DfA9F95A105',
- '0xe92401A4d3af5E446d93D11EEc806b1462b39D15',
- '0x81A5D6E50C214044bE44cA0CB057fe119097850c'

My guess is, there's gotta be a way to get access to these addresses. To sign off transactions on EVM, one needs an EOA's private key to sign the keccak-256 hash of the RLP serialized tx data, of which the result is a signature:

- signature = F(keccak256(messgae), privateKey), where F is the signing algo
* detail can be found [here](https://github.com/ethereumbook/ethereumbook/blob/develop/06transactions.asciidoc)

Therefore, my guess is the hex data could be related to private keys. However, private key is a 32 byte hexadecimal value, which is different from what's given in the challenge. Puting the hex into google, many results indicate that it could be utf-8 encoded. Javascript provides a convinient method to decode it, and the results are:
- MHhjNjc4ZWYxYWE0NTZkYTY1YzZmYzU4NjFkNDQ4OTJjZGZhYzBjNmM4YzI1NjBiZjBjOWZiY2RhZTJmNDczNWE5
- MHgyMDgyNDJjNDBhY2RmYTllZDg4OWU2ODVjMjM1NDdhY2JlZDliZWZjNjAzNzFlOTg3NWZiY2Q3MzYzNDBiYjQ4

The next took me a little while to crack. The above two strings are base64, which can be converted to hex data. The conversion gives us:
- 0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
- 0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48 

With private key, we can use public key recovery method to get the public key, we can hash the public and take the first 20 bytes, which will be the address assocaited with the private key. If the the address matches one of the three `TRUSTED_SOURCE_ROLES`, that means they are indeed the private keys. If that's the case, we can sign off transaction "on behalf" of them. It turns out they are the private keys of two of the `TRUSTED_SOURCE_ROLES`. Now, the hardest part is done. We can perform the aforementioned steps as follows: 

```
// load two private keys
let {privateKey1, privateKey2} = require("./decoder");

//create new wallets
let wallet1 = new ethers.Wallet(privateKey1, attacker.provider);
let wallet2 = new ethers.Wallet(privateKey2, attacker.provider);

// attack function 
let attack = async () => {
    await this.oracle.connect(wallet1).postPrice("DVNFT", ethers.utils.parseUnits('0', 'wei'));
    await this.oracle.connect(wallet2).postPrice("DVNFT", ethers.utils.parseUnits('0', 'wei'));

    // await this.oracle.getMedianPrice("DVNFT")
    // buy one with lowered price median
    await this.exchange.connect(attacker).buyOne({value: 1});

    // elevate the median price back 
    await this.oracle.connect(wallet1).postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
    await this.oracle.connect(wallet2).postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);

    // approve transaction
    await this.nftToken.connect(attacker).approve(this.exchange.address, 0);
    await this.exchange.connect(attacker).sellOne(0);

    // restore the NFT price to previous level
    await this.oracle.connect(wallet1).postPrice("DVNFT", INITIAL_NFT_PRICE);
    await this.oracle.connect(wallet2).postPrice("DVNFT", INITIAL_NFT_PRICE);

}

await attack();
```

8. Puppet

This challenge asks challenger to steal all of the funds from a lending pool. The lending pool uses uniswap v1 contracts to facilitate liquidity. My original idea was to manipulate the uniswap liquidity pool, but a quick glance of the contract revealed that there's a flaw in the `_computeOraclePirce()` function: it returns 0 when nominator is smaller than denominator. The correct way to calculate the ratio should've been multiplying the `uniswap.balance` by `amount` before division, but it failed to do so here. To exploit this vulnerability, the steps are:
- swap token for ETH to bring down the ETH balance in the pool;
- when the ETH balance is smaller than the token balance, call the `borrow()` function. 

Attack can be carried out as follows:
```
/** CODE YOUR EXPLOIT HERE */
// approve transcation
await this.token.connect(attacker).approve(
    this.uniswapExchange.address, 
    ATTACKER_INITIAL_TOKEN_BALANCE
);
// swap token for eth to change the pool dynamic
await this.uniswapExchange.connect(attacker).tokenToEthSwapInput(
    // sub(1) cuz test requires attacker has more balance than POOL_INITIAL_TOKEN_BALANCE
    ATTACKER_INITIAL_TOKEN_BALANCE.sub(1),
    1,
    (await ethers.provider.getBlock('latest')).timestamp * 2,   // deadline
);
// borrow
await this.lendingPool.connect(attacker).borrow(
    POOL_INITIAL_TOKEN_BALANCE, 
    {value: await this.lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE)}
);
```