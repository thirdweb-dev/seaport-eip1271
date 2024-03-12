// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("Token", "TOK") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
