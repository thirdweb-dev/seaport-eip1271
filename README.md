# Seaport bulk listings: EIP-1271 support

This project contains an [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271) `isValidSignature` function implementation that supports validating signatures produced on signing a [Seaport](https://github.com/ProjectOpenSea/seaport) bulk order payload.

- [`src/SeaportEIP1271.sol`](https://github.com/thirdweb-dev/seaport-eip1271/blob/main/src/SeaportEIP1271.sol): the `EIP1271.isValidSignature` implementation that supports validating Seaport bulk order signatures.
- [`src/SeaportOrderParser.sol`](): a helper contract with low-level code for working with Seaport data types, adapted from [GettersAndDerivers](https://github.com/ProjectOpenSea/seaport-core/blob/main/src/lib/GettersAndDerivers.sol) and [Verifiers](https://github.com/ProjectOpenSea/seaport-core/blob/d4e8c74adc472b311ab64b5c9f9757b5bba57a15/src/lib/Verifiers.sol#L151) in the [seaport-core repository](https://github.com/ProjectOpenSea/seaport-core/).
- [`test/SeaportOrderEIP1271.t.sol`](https://github.com/thirdweb-dev/seaport-eip1271/blob/main/test/SeaportEIP1271.t.sol): contains a minimal test case that fulfills a bulk order made/signed on behalf of a smart contract inheriting `SeaportEIP1271`. This minimal test case has been adapted from a [bulk order test in the seaport respository](https://github.com/ProjectOpenSea/seaport/blob/main/test/foundry/BulkSignature.t.sol#L47).

## Methodology

From [Seaport documentation](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md):

> A bulk signature is an EIP 712 type Merkle tree where the root is a BulkOrder and the leaves are OrderComponents. Each level will be either a pair of orders or an order and an array. Each level gets hashed up the tree until it’s all rolled up into a single hash, which gets signed. The signature on the rolled up hash is the ECDSA signature referred to throughout.

In other words, a bulk signature is produced on the root of the bulk order tree, which contains the bulk order's individual order components as its leaves.

When a bulk order is made on behalf of a smart contract actor -- by setting the smart contract's address as the signer of a bulk signature -- Seaport will call the `EIP1271.isValidSignature` function on the signer contract to validate the bulk signature.

The `isValidSignature` function receives as arguments:

1. a `bytes32` input `_message_` i.e. a digest derived only from the relevant bulk order payload. The digest signed by a signer to create a bulk signature is ultimately derived from this message hash.
2. a `bytes` input `_signature` which is the signature-to-validate, with the proof of inclusion of a single given order in the bulk order tree appended to the signature, in case of bulk orders.

```solidity
function isValidSignature(bytes32 _message, bytes memory _signature)
        public
        view
        virtual
        returns (bytes4 magicValue)
```

If the length of `_signature` is greater than `65`, the function assumes it is not dealing with a regular ECDSA signature of length 65 bytes, and is instead dealing with a Seaport bulk signature, which is guaranteed to have length >65 bytes.

From [Seaport documentation](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md):

> The recipe for a valid bulk signature is: A 64 or 65 byte ECDSA signature + a three byte index + a series of 32 byte proof elements up to 24 proofs long

```solidity
function isValidSignature(bytes32 _message, bytes memory _signature)
        public
        view
        virtual
        returns (bytes4 magicValue)
    {
        bytes32 targetDigest;
        bytes memory targetSig;

        if (_signature.length > 65) {
            // Handle Seaport bulk order signatures that are >65 bytes in length.
        } else {
            // Handle signature as if it is a regular ECDSA signature of length 65.
        }

        // ...snip
```

In the signature validation that the `isValidSignature` function must now perform, the function must first reconstruct the root of the bulk order tree using (a) the mentioned proof-of-inclusion, and (b) the leaf that represents the one order from the bulk order being processed. That's because the bulk order tree root is the actual message that an end user signs off on when sending a bulk order, and that's what is used along with a signature to recover signer address.

In the `isValidSignature` function, we already have (a) as just mentioned, however getting (b) requires passing along the relevant order parameters as extra data in the bytes input of the function.that the SeaportOrderEIP1271 contract is expecting you to send along in the bytes input of the isValidSignature function.

```solidity
function isValidSignature(bytes32 _message, bytes memory _signature)
        public
        view
        virtual
        returns (bytes4 magicValue)
    {
        bytes32 targetDigest;
        bytes memory targetSig;

        if (_signature.length > 65) {
            // Handle Seaport bulk order signatures that are >65 bytes in length.

            // Decode packed signature and order parameters.
            (bytes memory extractedPackedSig, OrderParameters memory orderParameters, uint256 counter) =
                abi.decode(_signature, (bytes, OrderParameters, uint256));
        } else {
            // Handle signature as if it is a regular ECDSA signature of length 65.
        }

        // ...snip
```

Once the bulk order tree root is reconstructed, the `isValidSignature` function can use this root to generate the actual digest that a signer has signed to produce the bulk signature in question. The contract then recovers the signer address from this digest and signature.

```solidity
function isValidSignature(bytes32 _message, bytes memory _signature)
        public
        view
        virtual
        returns (bytes4 magicValue)
    {
        bytes32 targetDigest;
        bytes memory targetSig;

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
            // Handle signature as if it is a regular ECDSA signature of length 65.
        }

        // ...snip
```

## Additional Resources

- Documentation for Seaport bulk order creation: [https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#bulk-order-creation](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#bulk-order-creation)
