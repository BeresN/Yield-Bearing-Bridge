// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {BridgeBank} from "../../src/source/BridgeBank.sol";
import {DestBridge} from "../../src/destination/DestBridge.sol";
import {BridgedToken} from "../../src/destination/BridgedToken.sol";
import {BridgeTypes} from "../../src/libraries/BridgeTypes.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockERC4626} from "../../src/mocks/MockERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title BridgeFuzzTest
 * @notice Fuzz tests for bridge operations
 */
contract BridgeFuzzTest is Test {
    BridgeBank public bridgeBank;
    MockERC20 public usdc;
    MockERC4626 public vault;

    DestBridge public destBridge;
    BridgedToken public bridgedToken;

    address constant OWNER = address(1);
    address public relayer;
    uint256 constant RELAYER_PK = 0x12345;
    address constant USER = address(3);

    uint256 constant MAX_DEPOSIT = 1_000_000_000e6; // 1B USDC
    uint256 constant MIN_DEPOSIT = 1e6; // 1 USDC

    bytes32 public destDomainSeparator;

    function setUp() public {
        relayer = vm.addr(RELAYER_PK);

        vm.startPrank(OWNER);
        usdc = new MockERC20("USD Coin", "USDC");
        vault = new MockERC4626(ERC20(address(usdc)), "Vault USDC", "vUSDC");
        bridgeBank = new BridgeBank(address(vault), OWNER);

        bridgedToken = new BridgedToken("Bridged USDC", "bUSDC");
        destBridge = new DestBridge(address(bridgedToken), relayer, OWNER);
        bridgedToken.setBridge(address(destBridge));
        vm.stopPrank();

        destDomainSeparator = destBridge.DOMAIN_SEPARATOR();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit(uint256 amount, address recipient) public {
        // Bound inputs
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        vm.assume(recipient != address(0));

        // Setup
        usdc.mint(USER, amount);

        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), amount);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: recipient,
            amount: amount,
            destinationChainId: 137
        });

        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Assertions
        assertEq(nonce, 1);
        assertEq(usdc.balanceOf(USER), 0);

        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);
        assertEq(record.amount, amount);
        assertEq(record.recipient, recipient);
    }

    function testFuzz_MultipleDeposits(
        uint8 numDeposits,
        uint256 baseAmount
    ) public {
        // Bound inputs
        numDeposits = uint8(bound(numDeposits, 1, 20));
        baseAmount = bound(baseAmount, MIN_DEPOSIT, MAX_DEPOSIT / 20);

        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < numDeposits; i++) {
            uint256 amount = baseAmount + (i * MIN_DEPOSIT);
            totalDeposited += amount;

            usdc.mint(USER, amount);

            vm.startPrank(USER);
            usdc.approve(address(bridgeBank), amount);

            BridgeTypes.DepositParams memory params = BridgeTypes
                .DepositParams({
                    recipient: address(uint160(i + 100)),
                    amount: amount,
                    destinationChainId: 137
                });

            bridgeBank.deposit(params);
            vm.stopPrank();
        }

        assertEq(bridgeBank.depositNonce(), numDeposits);
        assertApproxEqRel(
            bridgeBank.totalVaultAssets(),
            totalDeposited,
            0.001e18
        );
    }

    /*//////////////////////////////////////////////////////////////
                          YIELD FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_YieldDoesNotReduceAssets(
        uint256 depositAmount,
        uint256 yieldAmount
    ) public {
        // Bound inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        yieldAmount = bound(yieldAmount, 0, depositAmount); // Yield up to 100%

        // Deposit
        usdc.mint(USER, depositAmount);
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), depositAmount);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: address(0x999),
            amount: depositAmount,
            destinationChainId: 137
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        uint256 valueBeforeYield = bridgeBank.getDepositValue(nonce);

        // Add yield
        if (yieldAmount > 0) {
            vm.prank(OWNER);
            vault.simulateYield(yieldAmount);
        }

        uint256 valueAfterYield = bridgeBank.getDepositValue(nonce);

        // Invariant: Value should never decrease
        assertGe(valueAfterYield, valueBeforeYield);
    }

    function testFuzz_ShareConversion(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Deposit to get shares
        usdc.mint(USER, amount);
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), amount);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: address(0x999),
            amount: amount,
            destinationChainId: 137
        });
        bridgeBank.deposit(params);
        vm.stopPrank();

        // Get shares and convert back
        uint256 shares = bridgeBank.totalVaultShares();
        uint256 convertedAssets = vault.convertToAssets(shares);

        // Should be approximately equal (may have rounding)
        assertApproxEqRel(convertedAssets, amount, 0.001e18); // 0.1% tolerance
    }

    /*//////////////////////////////////////////////////////////////
                          MINT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) public {
        // Bound inputs
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        nonce = bound(nonce, 1, type(uint128).max);
        deadline = bound(deadline, block.timestamp, block.timestamp + 365 days);

        // Create message
        BridgeTypes.BridgeMessage memory message = BridgeTypes.BridgeMessage({
            depositor: USER,
            recipient: address(0x888),
            amount: amount,
            shares: amount,
            nonce: nonce,
            sourceChainId: 1,
            destinationChainId: block.chainid,
            deadline: deadline
        });

        // Sign
        bytes32 digest = SignatureUtils.getTypedDataHash(
            destDomainSeparator,
            message
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RELAYER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Mint
        destBridge.mint(message, signature);

        // Verify
        assertEq(bridgedToken.balanceOf(address(0x888)), amount);
        assertTrue(destBridge.usedNonces(nonce));
    }

    function testFuzz_CannotReuseNonce(uint256 nonce) public {
        nonce = bound(nonce, 1, type(uint128).max);

        BridgeTypes.BridgeMessage memory message = BridgeTypes.BridgeMessage({
            depositor: USER,
            recipient: address(0x888),
            amount: 1000e6,
            shares: 1000e6,
            nonce: nonce,
            sourceChainId: 1,
            destinationChainId: block.chainid,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = SignatureUtils.getTypedDataHash(
            destDomainSeparator,
            message
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RELAYER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First mint succeeds
        destBridge.mint(message, signature);

        // Second mint fails
        vm.expectRevert(
            abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, nonce)
        );
        destBridge.mint(message, signature);
    }

    /*//////////////////////////////////////////////////////////////
                        REFUND FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Refund(uint256 depositAmount, uint256 yieldBps) public {
        // Bound inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_DEPOSIT);
        yieldBps = bound(yieldBps, 0, 5000); // 0-50% yield

        // Deposit
        usdc.mint(USER, depositAmount);
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), depositAmount);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: address(0x999),
            amount: depositAmount,
            destinationChainId: 137
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Add yield - minting to vault naturally increases share value
        if (yieldBps > 0) {
            uint256 yieldAmount = (depositAmount * yieldBps) / 10000;
            usdc.mint(address(vault), yieldAmount);
        }

        uint256 expectedValue = bridgeBank.getDepositValue(nonce);
        uint256 userBalanceBefore = usdc.balanceOf(USER);

        // Refund (minAmount = 0 for no slippage protection)
        vm.prank(OWNER);
        bridgeBank.refund(nonce, 0);

        uint256 userBalanceAfter = usdc.balanceOf(USER);
        uint256 refundedAmount = userBalanceAfter - userBalanceBefore;

        // Should receive at least original deposit
        assertGe(refundedAmount, depositAmount);
        // Should match expected value from shares
        assertApproxEqRel(refundedAmount, expectedValue, 0.001e18);
    }
}
