// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {BridgeTypes} from "../../src/libraries/BridgeTypes.sol";

/**
 * @title SignatureUtilsWrapper
 * @notice Wrapper contract to expose internal library functions for testing reverts
 */
contract SignatureUtilsWrapper {
    bytes32 public domainSeparator;

    constructor(address verifyingContract) {
        domainSeparator = SignatureUtils.computeDomainSeparator(
            verifyingContract
        );
    }

    function recoverSigner(
        bytes32 digest,
        bytes memory signature
    ) external pure returns (address) {
        return SignatureUtils.recoverSigner(digest, signature);
    }

    function verifyOrRevert(
        BridgeTypes.BridgeMessage memory message,
        bytes memory signature,
        address expectedSigner
    ) external view {
        SignatureUtils.verifyOrRevert(
            domainSeparator,
            message,
            signature,
            expectedSigner
        );
    }

    function checkDeadline(uint256 deadline) external view {
        SignatureUtils.checkDeadline(deadline);
    }
}

/**
 * @title SignatureUtilsTest
 * @notice Unit tests for SignatureUtils library
 */
contract SignatureUtilsTest is Test {
    SignatureUtilsWrapper public wrapper;
    bytes32 public domainSeparator;
    address constant VERIFYING_CONTRACT = address(0x1234);

    uint256 constant SIGNER_PK = 0x12345;
    address public signer;

    function setUp() public {
        signer = vm.addr(SIGNER_PK);
        wrapper = new SignatureUtilsWrapper(VERIFYING_CONTRACT);
        domainSeparator = SignatureUtils.computeDomainSeparator(
            VERIFYING_CONTRACT
        );

        vm.label(signer, "Signer");
        vm.label(VERIFYING_CONTRACT, "VerifyingContract");
    }

    function _createMessage()
        internal
        pure
        returns (BridgeTypes.BridgeMessage memory)
    {
        return
            BridgeTypes.BridgeMessage({
                depositor: address(0x111),
                recipient: address(0x222),
                amount: 1000e6,
                shares: 1000e6,
                nonce: 1,
                sourceChainId: 1,
                destinationChainId: 137,
                deadline: 1000000
            });
    }

    function _signDigest(
        bytes32 digest,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                        DOMAIN SEPARATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ComputeDomainSeparator() public view {
        bytes32 separator = SignatureUtils.computeDomainSeparator(
            VERIFYING_CONTRACT
        );

        // Should produce consistent results
        assertEq(separator, domainSeparator);

        // Should be non-zero
        assertTrue(separator != bytes32(0));
    }

    function test_DomainSeparatorDifferentContracts() public view {
        bytes32 separator1 = SignatureUtils.computeDomainSeparator(
            address(0x1111)
        );
        bytes32 separator2 = SignatureUtils.computeDomainSeparator(
            address(0x2222)
        );

        assertFalse(separator1 == separator2);
    }

    /*//////////////////////////////////////////////////////////////
                          STRUCT HASHING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HashBridgeMessage() public pure {
        BridgeTypes.BridgeMessage memory message = _createMessage();

        bytes32 hash1 = SignatureUtils.hashBridgeMessage(message);
        bytes32 hash2 = SignatureUtils.hashBridgeMessage(message);

        // Should be deterministic
        assertEq(hash1, hash2);
        assertTrue(hash1 != bytes32(0));
    }

    function test_HashBridgeMessageDifferentData() public pure {
        BridgeTypes.BridgeMessage memory message1 = _createMessage();
        BridgeTypes.BridgeMessage memory message2 = _createMessage();
        message2.amount = 2000e6;

        bytes32 hash1 = SignatureUtils.hashBridgeMessage(message1);
        bytes32 hash2 = SignatureUtils.hashBridgeMessage(message2);

        assertFalse(hash1 == hash2);
    }

    /*//////////////////////////////////////////////////////////////
                        TYPED DATA HASH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetTypedDataHash() public view {
        BridgeTypes.BridgeMessage memory message = _createMessage();

        bytes32 hash = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );

        assertTrue(hash != bytes32(0));

        // Should be deterministic
        bytes32 hash2 = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        assertEq(hash, hash2);
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecoverSigner() public view {
        BridgeTypes.BridgeMessage memory message = _createMessage();
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );

        bytes memory signature = _signDigest(digest, SIGNER_PK);
        address recovered = SignatureUtils.recoverSigner(digest, signature);

        assertEq(recovered, signer);
    }

    function test_RevertWhen_InvalidSignature() public {
        bytes32 digest = keccak256("test");
        bytes memory badSignature = new bytes(65);

        vm.expectRevert(BridgeTypes.InvalidSignature.selector);
        wrapper.recoverSigner(digest, badSignature);
    }

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Verify() public view {
        BridgeTypes.BridgeMessage memory message = _createMessage();
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        bytes memory signature = _signDigest(digest, SIGNER_PK);

        bool valid = SignatureUtils.verify(
            domainSeparator,
            message,
            signature,
            signer
        );

        assertTrue(valid);
    }

    function test_VerifyWrongSigner() public view {
        BridgeTypes.BridgeMessage memory message = _createMessage();
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        bytes memory signature = _signDigest(digest, SIGNER_PK);

        bool valid = SignatureUtils.verify(
            domainSeparator,
            message,
            signature,
            address(0x999)
        );

        assertFalse(valid);
    }

    function test_VerifyOrRevert() public view {
        BridgeTypes.BridgeMessage memory message = _createMessage();
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        bytes memory signature = _signDigest(digest, SIGNER_PK);

        // Should not revert
        SignatureUtils.verifyOrRevert(
            domainSeparator,
            message,
            signature,
            signer
        );
    }

    function test_RevertWhen_VerifyOrRevertInvalidSigner() public {
        BridgeTypes.BridgeMessage memory message = _createMessage();
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        bytes memory signature = _signDigest(digest, SIGNER_PK);

        vm.expectRevert(BridgeTypes.InvalidSignature.selector);
        wrapper.verifyOrRevert(message, signature, address(0x999));
    }

    /*//////////////////////////////////////////////////////////////
                          DEADLINE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckDeadline() public view {
        // Should not revert for future deadline
        SignatureUtils.checkDeadline(block.timestamp + 1 hours);
    }

    function test_CheckDeadlineExact() public view {
        // Should not revert for current timestamp
        SignatureUtils.checkDeadline(block.timestamp);
    }

    function test_RevertWhen_DeadlineExpired() public {
        uint256 pastDeadline = block.timestamp - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeTypes.SignatureExpired.selector,
                pastDeadline,
                block.timestamp
            )
        );
        wrapper.checkDeadline(pastDeadline);
    }
}
