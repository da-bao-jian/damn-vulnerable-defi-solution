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

9. Puppet V2

This is the continuation of the last challenge. The only difference is the pool get its price oracle from a liquidity pool on Uniswap. To solve this challenge, I can implement my original guess for the last challenge - oracle manipulation. To do so, we can use swap our token to receive ETH to drive down the price of the token. After the swap, if the return value of `calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE)` is smaller than the ETH balance of attacker's contract, then we can convert ETH into WETH and burrow all of the token from the lending pool.    

Attack can be carried out as follows:
```
// approve the uniswap router for swap
await this.token.connect(attacker).approve(this.uniswapRouter.address, ATTACKER_INITIAL_TOKEN_BALANCE);

// swap to change the pool dynamic
await this.uniswapRouter.connect(attacker).swapExactTokensForETH(
    ATTACKER_INITIAL_TOKEN_BALANCE,
    0, 
    [this.token.address, this.weth.address],
    attacker.address,
    (await ethers.provider.getBlock('latest')).timestamp * 2,   // deadline
);

// calculate amount of WETH needed to deposit for getting all of the token in the pool
let collateralInETH = await this.lendingPool.connect(attacker).calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);

// get balance of ETH after the swap and compare if there's enough ETH to get all of the token in the pool
let etherBal = await ethers.provider.getBalance(attacker.address);
etherBal > collateralInETH ? NaN : console.log("Not enough ETH to meet deposit of WETH required")

// wrap the ETH
await this.weth.connect(attacker).deposit({value: collateralInETH});

// approve the lending pool
await this.weth.connect(attacker).approve(this.lendingPool.address, collateralInETH);

// get all of the token in the poool
await this.lendingPool.connect(attacker).borrow(POOL_INITIAL_TOKEN_BALANCE); 
```
10. Free rider

This challenge asks to steal NFTs for a buyer. The buyer would pay 45 ETH for whoever is willing to take the NFT out from a NFT marketplace. The challenger is seeded with only 0.5 ETH, and a Uniswap pool is provided. The challenge also hinted that it would be helpful to get free ETH, even for an instant.  

To approach this, I thought about using flash loan, however, the two available contracts do not provide flash loan functionalities. A quick Google search revealed that Uniswap has its own version of flash loan - flash swap. 

Accoring to Uniswap's Doc, 

```
Uniswap flash swaps allow you to withdraw up to the full reserves of any ERC20 token on Uniswap and execute arbitrary logic at no upfront cost, provided that by the end of the transaction you either:

- pay for the withdrawn ERC20 tokens with the corresponding pair tokens
- return the withdrawn ERC20 tokens along with a small fee
```

To use flash swap, Uniswap provides the function `swap()`. 

Now, we have the capital required, let's dive into the challenge. The challenge has two contracts: `FreeRiderBuyer` and `FreeRiderNFTMarketplace`. `FreeRiderBuyer` does only one thing, which is to transfer the bounty from the buyer. Therefore, my guess is the exploitable code should live in `FreeRiderNFTMarketplace`. The `FreeRiderNFTMarketplace` does two things, buy and sell NFTs in batch. The buy functions are called in the initial setup of the test, where 6 `DamnValuableNFT` were put up for sale. To get the NFTs, I need to use the `buyMany()` function. A quick examination revealed a critical flaw in its design:
- `buyMany()` function uses a helper function named `_buyOne()` to process individual purchases;
- `_buyOne()` checks the `msg.value` when an external actor calls the `buyMany()` function, but it compares the `msg.value` against the unit price of a NFT. For instance, if one wants to buy all 6 of `DamnValuableNFT`, he/she needs to send 90ETH. But because `_buyOne()` only checks `msg.value` against the uni price of a NFT, one only needs to send 15ETH to receive all 6 of `DmnValuableNFT`;
- Additionally, because `_buyOne()` also pays the seller from the balance of the `FreeRiderNFTMarketplace` contract, any purchase would decrease the balance of the contract. If one buys all 6 of the NFTs, it would reduce the contract balance to zero since `FreeRiderNFTMarketplace` was seeded with 90ETH in balance. 

An attack vector could be carried out as such: 
- implement the `IUniswapV2Callee` interface for the attacking contract;
- in the `uniswapV2Call()` function:
  - use flash swap to get 15 WETH;
  - unwrap WETH to ETH and call the `buyMany()` method;
  - wrap ETH back to WETH and return to the borrowed amount including the fees;
- send the received NFT to the buyer. 

`uniswapV2Call()` function belongs to the `IUniswapV2Callee` interface, which would be invoked indirectly by the `swap()` function. 

Again, DON'T FORGET TO ADD `receive()` function in your attacking contract. 

11. Backdoor

You can read @tinchoabbate's detailed walkthrough of this vulnerability [here](https://blog.openzeppelin.com/backdooring-gnosis-safe-multisig-wallets/)

If you've read all of my previous challenge breakdowns and understood my approach, you should start this challenge by finding the `transfer` function since the goal is to take all of the fund from registry. Once you are able to find the `transfer()` function, you should work your way backward step by step. This should lead you to this line:
```
address payable walletAddress = payable(proxy);
```
To steal all of the fund, we need to be able to change the `walletAddress` to our attack contract's address. To do so we need to figure out what's `proxy`?

It's the first argument of the `proxyCreated()` function, and an instance of `GnosisSafeProxy`. According to the comment, `proxyCreated()` will be executed when one creates a new wallet via the `createProxyWithCallback()` method. The next logical step is to find out what does `createProxyWithCallback()` do and how we can tinker around it to modify `proxy`. Here's its implementation: 
```
/// @dev Allows to create new proxy contact, execute a message call to the new proxy and call a specified callback within one transaction
/// @param _singleton Address of singleton contract.
/// @param initializer Payload for message call sent to new proxy contract.
/// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
/// @param callback Callback that will be invoced after the new proxy contract has been successfully deployed and initialized.

function createProxyWithCallback(
    address _singleton,
    bytes memory initializer,
    uint256 saltNonce,
    IProxyCreationCallback callback
) public returns (GnosisSafeProxy proxy) {
    uint256 saltNonceWithCallback = uint256(keccak256(abi.encodePacked(saltNonce, callback)));
    proxy = createProxyWithNonce(_singleton, initializer, saltNonceWithCallback);
    if (address(callback) != address(0)) callback.proxyCreated(proxy, _singleton, initializer, saltNonc);
}
```

`proxy` is the variable we need to modify. To do so, we need to trace up to the function where `proxy` was calculated. This should lead to the `deployProxyWithNonce()` function in the `GnosisSafeProxyFactory` contract. Here's its implementation: 
```
function deployProxyWithNonce(
    address _singleton,
    bytes memory initializer,
    uint256 saltNonce
) internal returns (GnosisSafeProxy proxy) {
    // If the initializer changes the proxy address should change too. Hashing the initializer data is cheaper than just concatinating it
    bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));
    bytes memory deploymentData = abi.encodePacked(type(GnosisSafeProxy).creationCode, uint256(uint160(_singleton)));
    // solhint-disable-next-line no-inline-assembly
    assembly {
        proxy := create2(0x0, add(0x20, deploymentData), mload(deploymentData), salt)
    }
    require(address(proxy) != address(0), "Create2 call failed");
}
```
We can see that `proxy` is created via the `CREATE2` opcode. The difference between `CREATE1` and `CREATE2` is that when deploying a contract using `CREATE2`, it includes a hash of the bytecode being deployed and a randome `salt` provided by the deployer. It looks like this:
```
keccak256(0xff ++ deployingAddress ++ salt ++ keccak256(bytecode))[12:]
``` 
where 
- `0xff` is used to prevent hash collision with `CREATE`;
- `deployingAddress` is the sender's address;
- `salt` is the arbitrary value provided by the sender;
- `keccak256(bytecode)` is the contract's bytecode;
- `[12:]` first 12 bytes are removed. 

By comparison, `CREATE` would look like this:
```
keccak256(rlp.encode(deployingAddress, nonce))[12:]
```
where
- `deployingAddress` is the sender's address;
- `nonce` a sequential number to keep a track of number of contracts created.

`CREATE2` allows depoloyer to pre-compute the contract address. The benefit of it is that an address could be generated without deployment, which opens the possibility of scalability and better user onboarding experience. 

Back to the challenge. We can see that `proxy` variable depends on `create2(0x0, add(0x20, deploymentData), mload(deploymentData), salt)`. The for arguments are:
- `0x0`: amount of wei sent to the new contract;
- `add(0x20, deploymentData), mload(deploymentData)` location of the bytecode in memory;
- `salt` an arbitrary 32 bytes value. 

Here, since `type(GnosisSafeProxy).creationCode` and `_singleton` are fixed, we don't need to worry about `deploymentData`. Let's take a look at how `salt` is generated. 
```
bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));
```
`salt` is generated by a hash of hashed `initializer` and `saltNonce`, where the `initializer` should be the `setup()` function in `GnosisSafe` contract
```
function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address to,
    bytes calldata data,
    address fallbackHandler,
    address paymentToken,
    uint256 payment,
    address payable paymentReceiver
) external {
    // setupOwners checks if the Threshold is already set, therefore preventing that this method is called twice
    setupOwners(_owners, _threshold);
    if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);
    // As setupOwners can only be called if the contract has not been initialized we don't need a check for setupModules
    setupModules(to, data);

    if (payment > 0) {
        // To avoid running into issues with EIP-170 we reuse the handlePayment function (to avoid adjusting code of that has been verified we do not adjust the method itself)
        // baseGas = 0, gasPrice = 1 and gas = payment => amount = (payment + 0) * 1 = payment
        handlePayment(payment, 0, 1, paymentToken, paymentReceiver);
    }
    emit SafeSetup(msg.sender, _owners, _threshold, to, fallbackHandler);
  }
```
and `saltNonce` should be
```
// saltUint256 is the address of users casted into an unit256 
uint256 saltNonce = uint256(keccak256(abi.encodePacked(saltUin256, callback)));
```

Therefore, in order to modify `proxy`, we need to modify `initializer` and `saltNonce` accordingly. Looking at the `setup()` function, there are a few parameters we could tweak to fit our need:
- change `_owners` to existing owners, namely, Alice, Bob, Charlie, David;
- change `to` to the deployed attacking contract';
- change `data` to execute a `delegatecall` to whatever address is passed. 

Because we want to transfer token to proxy, we should encode an ERC20 style `approve()` function approving attacking contract's address as the `data` parameter. 

If you receive errors saying "Error: Transaction reverted without a reason string", it's very likely you ran out of gas because of this line in the `GnosisSafeProxyFactory`:
```
if eq(call(gas(), proxy, 0, add(initializer, 0x20), mload(initializer), 0, 0), 0) {
    revert(0, 0)
}
```
If that's the case, try declaring variables as `immutable`. 

12. Climber

If you followed my previous approches, you should be looking at `sweepFunds()` function in the `ClimberValut` contract. However, `sweepFunds()` can only be called by `sweeper`, which is priviledged role initialized in the `initializer()` function. Because `ClimberVault` uses a `initializer()` function and an empty constructor, we can tell that it follows the [UUPS](https://eips.ethereum.org/EIPS/eip-1822) pattern. Which means, we might be able to upgrade the contract through a proxy contract. 

There are many details need to be followed when writing upgradable contracts. For instance, constructor should not be used since the code within will never be executed in the context of a proxy contract's state. Additionally, field declaration should be avoided as this is equivalent to declaring them in a constructor unless they are defined as `constant` state variable.

For `ClimberVault`, we can see that it inherits from OpenZepplin's `UUPSUpgradeable` contract, which includes a `virtual` function named `_authorizeUpgrade()`. Here, `ClimberVault` also has a function named `_authorizeUpgrade()` that should be overriding the same function from `UUPSUpgradeable`. The only issue is, it has `onlyOwner` modifier. The current owner is the `ClimberTimelock` contract. Therefore, we need to take control of `ClimberTimelock`. Good news is `ClimberTimelock` inherits `AccessControl`, and in the constructor `ClimberTimelock` is a self admin. In other words, we can call `AccessControl.grantRole()` to the attacking contract. 

To interact with the upgraded contract, we can use the `execute()` method in the `ClimberTimelock`, which execute three arrays of sequential calls. These arrays are filled by calling the `schedule()` function. There's a hard coded `delay` to execute scheduled calls, but since we are the `PROSER_ROLE` now we can use the `updateDelay` to change it to zero. After that, we can change the `sweepFunds()` function to fit our need, namely deleting the modifier and change the transfer address to ourselves.

To execute the exploit, in the attack contract, we need to do the following:
- change the proser_role of the climbertimelock contract
- change delay time
- upgrade logic contract from proxy
- schedule all the sequential calls 
- execute the sequential call


