// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Base test util
import {Test} from "forge-std/Test.sol";

// Target contract to test
import {SeaportEIP1271} from "src/SeaportEIP1271.sol";

// Test util contracts
import {Seaport} from "./utils/Seaport.sol";
import {MockERC721} from "./utils/MockERC721.sol";
import {EIP712MerkleTree} from "./utils/EIP712MerkleTree.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";

// Test util types
import {
    ConsiderationItem,
    OfferItem,
    ItemType,
    SpentItem,
    ReceivedItem,
    OrderComponents,
    Order,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

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
    SeaportSigValidator private validator;

    // Mock seaport contracts
    Seaport private seaport;
    ConduitController private conduitController;

    // Mock token contract
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

    // Test event
    event OrderFulfilled(
        bytes32 orderHash,
        address indexed offerer,
        address indexed zone,
        address recipient,
        SpentItem[] offer,
        ReceivedItem[] consideration
    );

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
        // Setup seaport contracts
        conduitController = new ConduitController();
        seaport = new Seaport(address(conduitController));

        // Setup signer.
        string memory offerer = "offerer";
        (address addr, uint256 key) = makeAddrAndKey(offerer);

        accountAdmin = addr;
        accountAdminPKey = key;

        vm.deal(accountAdmin, 100 ether);

        // Setup mock ERC721 token contract and mint NFT to signer
        erc721 = new MockERC721();
        erc721.mint(address(accountAdmin), 1);

        vm.prank(accountAdmin);
        erc721.setApprovalForAll(address(seaport), true);

        // Setup signature validator contract
        vm.prank(accountAdmin);
        validator = new SeaportSigValidator();
    }

    function test_bulkOrder() public {
        // Setup seaport bulk order params
        _configureConsiderationItems();
        _configureOrderParameters(address(validator));
        _configureOrderComponents(seaport.getCounter(accountAdmin));

        OrderComponents[] memory orderComponents = new OrderComponents[](3);
        orderComponents[0] = baseOrderComponents;
        // The other order components can remain empty.

        // Sign the bulk order and get a bulk order signature.
        EIP712MerkleTree merkleTree = new EIP712MerkleTree();
        bytes memory packedSignature = merkleTree.signBulkOrder(
            ConsiderationInterface(address(seaport)), accountAdminPKey, orderComponents, uint24(0), false
        );

        Order memory order = Order({
            parameters: baseOrderParameters,
            signature: abi.encode(packedSignature, baseOrderParameters, seaport.getCounter(accountAdmin))
        });

        // The bulk order signature is 132 bytes long. Per Seaport documentation (https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#bulk-order-creation)
        // the tested bulk order signature is made up of: 65 byte ECDSA signature + a 3 byte index +  a series of 32 byte proof elements up to 24 proofs long.
        //
        // So this particular signature is 65 + 3 + 32 * 2 = 132 bytes long. Here, '32 * 2' because we are sending only one order + one empty order
        // (resulting in a bulk order tree of 2 ^ 1 orders).
        assertEq(packedSignature.length, 132);

        // We expect the signature to be valid, and to be sent on behalf of `validator` contract as the signer.
        vm.expectEmit(true, false, false, false, address(seaport));
        emit OrderFulfilled(
            bytes32(0), address(validator), address(0), address(0), new SpentItem[](0), new ReceivedItem[](0)
        );
        seaport.fulfillOrder{value: 1}(order, bytes32(0));
    }
}
