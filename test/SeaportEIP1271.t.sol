// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SeaportEIP1271} from "src/SeaportEIP1271.sol";
import {EIP712MerkleTree} from "./utils/EIP712MerkleTree.sol";
import {ERC721} from "@solady/tokens/ERC721.sol";

import {Seaport} from "./utils/Seaport.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";

import {
    ConsiderationItem,
    OfferItem,
    ItemType,
    SpentItem,
    OrderComponents,
    Order,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {OrderType, BasicOrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {OrderParameters} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
    Create2AddressDerivation_length,
    Create2AddressDerivation_ptr,
    EIP_712_PREFIX,
    EIP712_ConsiderationItem_size,
    EIP712_DigestPayload_size,
    EIP712_DomainSeparator_offset,
    EIP712_OfferItem_size,
    EIP712_Order_size,
    EIP712_OrderHash_offset,
    FreeMemoryPointerSlot,
    information_conduitController_offset,
    information_domainSeparator_offset,
    information_length,
    information_version_cd_offset,
    information_version_offset,
    information_versionLengthPtr,
    information_versionWithLength,
    MaskOverByteTwelve,
    MaskOverLastTwentyBytes,
    OneWord,
    OneWordShift,
    OrderParameters_consideration_head_offset,
    OrderParameters_counter_offset,
    OrderParameters_offer_head_offset,
    TwoWords
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    BulkOrderProof_keyShift,
    BulkOrderProof_keySize,
    BulkOrder_Typehash_Height_One,
    BulkOrder_Typehash_Height_Two,
    BulkOrder_Typehash_Height_Three,
    BulkOrder_Typehash_Height_Four,
    BulkOrder_Typehash_Height_Five,
    BulkOrder_Typehash_Height_Six,
    BulkOrder_Typehash_Height_Seven,
    BulkOrder_Typehash_Height_Eight,
    BulkOrder_Typehash_Height_Nine,
    BulkOrder_Typehash_Height_Ten,
    BulkOrder_Typehash_Height_Eleven,
    BulkOrder_Typehash_Height_Twelve,
    BulkOrder_Typehash_Height_Thirteen,
    BulkOrder_Typehash_Height_Fourteen,
    BulkOrder_Typehash_Height_Fifteen,
    BulkOrder_Typehash_Height_Sixteen,
    BulkOrder_Typehash_Height_Seventeen,
    BulkOrder_Typehash_Height_Eighteen,
    BulkOrder_Typehash_Height_Nineteen,
    BulkOrder_Typehash_Height_Twenty,
    BulkOrder_Typehash_Height_TwentyOne,
    BulkOrder_Typehash_Height_TwentyTwo,
    BulkOrder_Typehash_Height_TwentyThree,
    BulkOrder_Typehash_Height_TwentyFour,
    EIP712_domainData_chainId_offset,
    EIP712_domainData_nameHash_offset,
    EIP712_domainData_size,
    EIP712_domainData_verifyingContract_offset,
    EIP712_domainData_versionHash_offset,
    FreeMemoryPointerSlot,
    NameLengthPtr,
    NameWithLength,
    OneWord,
    Slot0x80,
    ThreeWords,
    ZeroSlot
} from "seaport-types/src/lib/ConsiderationConstants.sol";

contract MockERC721 is ERC721 {
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract SeaportSigValidator is SeaportEIP1271 {
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    function _isAuthorizedSigner(address _signer) internal view override returns (bool) {
        return _signer == admin;
    }
}

contract SeaportEIP1271Test is Test {
    // Target contract
    ConduitController private conduitController;
    Seaport private seaport;
    SeaportSigValidator private validator;

    MockERC721 private erc721;

    // Signer
    uint256 private accountAdminPKey = 1;
    address private accountAdmin;

    // Test params
    OfferItem offerItem;
    OfferItem[] offerItems;
    ConsiderationItem considerationItem;
    ConsiderationItem[] considerationItems;
    OrderComponents baseOrderComponents;
    OrderParameters baseOrderParameters;

    // Helpers to setup test params
    function _configureOrderParameters(address offerer) internal {
        bytes32 conduitKey = bytes32(0);
        baseOrderParameters.offerer = offerer;
        baseOrderParameters.zone = address(0);
        baseOrderParameters.offer = offerItems;
        baseOrderParameters.consideration = considerationItems;
        baseOrderParameters.orderType = OrderType.FULL_OPEN;
        baseOrderParameters.startTime = block.timestamp;
        baseOrderParameters.endTime = block.timestamp + 1;
        baseOrderParameters.zoneHash = bytes32(0);
        baseOrderParameters.salt = 0;
        baseOrderParameters.conduitKey = conduitKey;
        baseOrderParameters.totalOriginalConsiderationItems = considerationItems.length;
    }

    function _configureConsiderationItems() internal {
        considerationItem.itemType = ItemType.NATIVE;
        considerationItem.token = address(0);
        considerationItem.identifierOrCriteria = 0;
        considerationItem.startAmount = 1;
        considerationItem.endAmount = 1;
        considerationItem.recipient = payable(address(0x123));
        considerationItems.push(considerationItem);
    }

    function _configureOrderComponents(uint256 counter) internal {
        baseOrderComponents.offerer = baseOrderParameters.offerer;
        baseOrderComponents.zone = baseOrderParameters.zone;
        baseOrderComponents.offer = baseOrderParameters.offer;
        baseOrderComponents.consideration = baseOrderParameters.consideration;
        baseOrderComponents.orderType = baseOrderParameters.orderType;
        baseOrderComponents.startTime = baseOrderParameters.startTime;
        baseOrderComponents.endTime = baseOrderParameters.endTime;
        baseOrderComponents.zoneHash = baseOrderParameters.zoneHash;
        baseOrderComponents.salt = baseOrderParameters.salt;
        baseOrderComponents.conduitKey = baseOrderParameters.conduitKey;
        baseOrderComponents.counter = counter;
    }

    function setUp() public {
        // Setup ERC721 contract
        erc721 = new MockERC721();

        // Setup signer.
        string memory offerer = "offerer";
        (address addr, uint256 key) = makeAddrAndKey(offerer);

        accountAdmin = addr;
        accountAdminPKey = key;

        vm.deal(accountAdmin, 100 ether);

        // Setup seaport contract
        conduitController = new ConduitController();
        seaport = new Seaport(address(0x123));

        // Setup validator contract
        vm.prank(accountAdmin);
        validator = new SeaportSigValidator();
    }

    function test_POC() public {
        // Mint NFT to admin address
        erc721.mint(address(accountAdmin), 1);
        vm.prank(accountAdmin);

        // Approve seaport contract to transfer NFT
        erc721.setApprovalForAll(address(seaport), true);

        // Setup seaport bulk order params
        _configureConsiderationItems();
        _configureOrderParameters(address(validator));
        _configureOrderComponents(seaport.getCounter(accountAdmin));

        OrderComponents[] memory orderComponents = new OrderComponents[](3);
        orderComponents[0] = baseOrderComponents;
        // The other order components can remain empty.

        EIP712MerkleTree merkleTree = new EIP712MerkleTree();
        bytes memory packedSignature = merkleTree.signBulkOrder(
            address(validator),
            ConsiderationInterface(address(seaport)),
            accountAdminPKey,
            orderComponents,
            uint24(0),
            false
        );

        Order memory order = Order({
            parameters: baseOrderParameters,
            signature: abi.encode(packedSignature, baseOrderParameters, seaport.getCounter(accountAdmin))
        });

        assertEq(packedSignature.length, 132);
        seaport.fulfillOrder{value: 1}(order, bytes32(0));
    }
}
