// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {SeaportOrderParser} from "./SeaportOrderParser.sol";
import {OrderParameters} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract SeaportEIP1271 is SeaportOrderParser {
    using ECDSA for bytes32;

    /// @notice The function selector of EIP1271.isValidSignature to be returned on sucessful signature verification.
    bytes4 public constant MAGICVALUE = 0x1626ba7e;

    /// @notice See EIP-1271: https://eips.ethereum.org/EIPS/eip-1271
    function isValidSignature(bytes32 _message, bytes memory _signature)
        public
        view
        virtual
        returns (bytes4 magicValue)
    {
        bytes32 targetDigest;
        bytes memory targetSig;

        // Handle OpenSea bulk order signatures that are >65 bytes in length.
        if (_signature.length > 65) {
            // Decode packed signature and order parameters.
            (bytes memory extractedPackedSig, OrderParameters memory orderParameters, uint256 counter) =
                abi.decode(_signature, (bytes, OrderParameters, uint256));

            // Verify that the original digest matches the digest built with order parameters.
            bytes32 domainSeparator = _buildSeaportDomainSeparator(msg.sender);
            bytes32 orderHash = _deriveOrderHash(orderParameters, counter);

            require(
                _deriveEIP712Digest(domainSeparator, orderHash) == _message,
                "Seaport: order hash does not match the provided message."
            );

            // Build bulk signature digest
            targetDigest = _deriveEIP712Digest(domainSeparator, _computeBulkOrderProof(extractedPackedSig, orderHash));

            // Extract the signature, which is the first 65 bytes
            targetSig = new bytes(65);
            for (uint256 i = 0; i < 65; i++) {
                targetSig[i] = extractedPackedSig[i];
            }
        } else {
            targetDigest = _message;
            targetSig = _signature;
        }

        address signer = targetDigest.recover(targetSig);

        if (_isAuthorizedSigner(signer)) {
            magicValue = MAGICVALUE;
        }
    }

    /// @notice Returns whether a given signer is an authorized signer for the contract.
    function _isAuthorizedSigner(address _signer) internal view virtual returns (bool);
}
