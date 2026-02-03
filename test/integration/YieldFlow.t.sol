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
 * @title YieldFlowTest
 * @notice Integration tests for full bridge flow with yield accrual
 */
contract YieldFlowTest is Test {
    // Source chain contracts
    BridgeBank public bridgeBank;
    MockERC20 public usdc;
    MockERC4626 public vault;

    // Destination chain contracts
    DestBridge public destBridge;
    BridgedToken public bridgedToken;

    // Actors
    address constant OWNER = address(1);
    address public relayer;
    uint256 constant RELAYER_PK = 0x12345;
    address constant USER = address(3);
    address constant RECIPIENT = address(4);

    // Constants
    uint256 constant INITIAL_BALANCE = 10_000e6;
    uint256 constant DEPOSIT_AMOUNT = 1000e6;
    uint256 constant SOURCE_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID = 137;

    bytes32 public destDomainSeparator;

    function setUp() public {
        relayer = vm.addr(RELAYER_PK);

        // Deploy source chain contracts
        vm.startPrank(OWNER);
        usdc = new MockERC20("USD Coin", "USDC");
        vault = new MockERC4626(ERC20(address(usdc)), "Vault USDC", "vUSDC");
        bridgeBank = new BridgeBank(address(vault), OWNER);
        bridgeBank.addChain(DEST_CHAIN_ID, address(0xDEAD)); // Add destination chain
        vm.stopPrank();

        // Deploy destination chain contracts
        vm.startPrank(OWNER);
        bridgedToken = new BridgedToken("Bridged USDC", "bUSDC");
        destBridge = new DestBridge(relayer, OWNER);
        destBridge.addSourceChain(SOURCE_CHAIN_ID, address(bridgedToken), address(0xBEEF));
        bridgedToken.setBridge(address(destBridge));
        vm.stopPrank();

        // Setup
        usdc.mint(USER, INITIAL_BALANCE);
        destDomainSeparator = destBridge.DOMAIN_SEPARATOR();

        // Labels
        vm.label(address(usdc), "USDC");
        vm.label(address(vault), "Vault");
        vm.label(address(bridgeBank), "BridgeBank");
        vm.label(address(bridgedToken), "BridgedToken");
        vm.label(address(destBridge), "DestBridge");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal returns (uint256 nonce, uint256 shares) {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), amount);

        BridgeTypes.DepositParams memory params =
            BridgeTypes.DepositParams({recipient: RECIPIENT, amount: amount, destinationChainId: DEST_CHAIN_ID});

        nonce = bridgeBank.deposit(params);
        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);
        shares = record.shares;
        vm.stopPrank();
    }

    function _createAndSignMessage(uint256 nonce, uint256 amount, uint256 shares, uint256 deadline)
        internal
        view
        returns (BridgeTypes.BridgeMessage memory message, bytes memory signature)
    {
        message = BridgeTypes.BridgeMessage({
            depositor: USER,
            recipient: RECIPIENT,
            amount: amount,
            shares: shares,
            nonce: nonce,
            sourceChainId: SOURCE_CHAIN_ID,
            destinationChainId: block.chainid,
            deadline: deadline
        });

        bytes32 digest = SignatureUtils.getTypedDataHash(destDomainSeparator, message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RELAYER_PK, digest);
        signature = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                        FULL BRIDGE FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullBridgeFlow() public {
        // Step 1: User deposits on source chain
        (uint256 nonce, uint256 shares) = _deposit(DEPOSIT_AMOUNT);

        assertEq(nonce, 1);
        assertEq(usdc.balanceOf(USER), INITIAL_BALANCE - DEPOSIT_AMOUNT);

        // Step 2: Relayer creates and signs message
        (BridgeTypes.BridgeMessage memory message, bytes memory signature) =
            _createAndSignMessage(nonce, DEPOSIT_AMOUNT, shares, block.timestamp + 1 hours);

        // Step 3: Mint on destination chain
        destBridge.mint(message, signature);

        assertEq(bridgedToken.balanceOf(RECIPIENT), DEPOSIT_AMOUNT);

        // Step 4: Mark as completed on source chain
        vm.prank(OWNER);
        bridgeBank.markCompleted(nonce);

        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);
        assertEq(uint8(record.status), uint8(BridgeTypes.DepositStatus.Completed));
    }

    function test_MultipleBridgeFlows() public {
        uint256 numDeposits = 5;

        for (uint256 i = 0; i < numDeposits; i++) {
            (uint256 nonce, uint256 shares) = _deposit(DEPOSIT_AMOUNT);

            (BridgeTypes.BridgeMessage memory message, bytes memory signature) =
                _createAndSignMessage(nonce, DEPOSIT_AMOUNT, shares, block.timestamp + 1 hours);

            destBridge.mint(message, signature);
        }

        assertEq(bridgedToken.balanceOf(RECIPIENT), DEPOSIT_AMOUNT * numDeposits);
        assertEq(usdc.balanceOf(USER), INITIAL_BALANCE - (DEPOSIT_AMOUNT * numDeposits));
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD ACCRUAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_YieldAccrualReflectedInShares() public {
        // Initial deposit
        (uint256 nonce,) = _deposit(DEPOSIT_AMOUNT);

        uint256 valueBeforeYield = bridgeBank.getDepositValue(nonce);
        assertEq(valueBeforeYield, DEPOSIT_AMOUNT);

        // Simulate 10% yield
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10;
        vm.prank(OWNER);
        vault.simulateYield(yieldAmount);

        uint256 valueAfterYield = bridgeBank.getDepositValue(nonce);
        assertGt(valueAfterYield, DEPOSIT_AMOUNT);

        // Value should have increased by approximately the yield
        assertApproxEqRel(valueAfterYield, DEPOSIT_AMOUNT + yieldAmount, 0.01e18); // 1% tolerance
    }

    function test_RefundWithAccruedYield() public {
        // Deposit
        (uint256 nonce,) = _deposit(DEPOSIT_AMOUNT);

        // Simulate 20% yield - minting to vault increases share value naturally
        uint256 yieldAmount = DEPOSIT_AMOUNT / 5;
        usdc.mint(address(vault), yieldAmount);

        uint256 userBalanceBefore = usdc.balanceOf(USER);

        // Refund (minAmount = 0 for no slippage protection)
        vm.prank(OWNER);
        bridgeBank.refund(nonce, 0);

        uint256 userBalanceAfter = usdc.balanceOf(USER);
        uint256 refundedAmount = userBalanceAfter - userBalanceBefore;

        // Should receive more than original deposit
        assertGt(refundedAmount, DEPOSIT_AMOUNT);
        assertApproxEqRel(refundedAmount, DEPOSIT_AMOUNT + yieldAmount, 0.01e18);
    }

    function test_MultipleDepositsWithYield() public {
        // First deposit
        (uint256 nonce1,) = _deposit(DEPOSIT_AMOUNT);

        // Simulate 10% yield
        vm.prank(OWNER);
        vault.simulateYield(DEPOSIT_AMOUNT / 10);

        // Second deposit (shares should be worth more now)
        (uint256 nonce2, uint256 shares2) = _deposit(DEPOSIT_AMOUNT);

        // Second deposit should get fewer shares due to increased share price
        BridgeTypes.DepositRecord memory record1 = bridgeBank.getDeposit(nonce1);
        assertGt(record1.shares, shares2);

        // But both deposits should have correct value
        uint256 value1 = bridgeBank.getDepositValue(nonce1);
        uint256 value2 = bridgeBank.getDepositValue(nonce2);

        assertGt(value1, DEPOSIT_AMOUNT); // Includes yield
        assertApproxEqRel(value2, DEPOSIT_AMOUNT, 0.01e18); // Just deposited amount
    }

    function test_TotalVaultAssetsWithYield() public {
        // Multiple deposits
        _deposit(DEPOSIT_AMOUNT);
        _deposit(DEPOSIT_AMOUNT);
        _deposit(DEPOSIT_AMOUNT);

        uint256 totalBeforeYield = bridgeBank.totalVaultAssets();
        assertEq(totalBeforeYield, DEPOSIT_AMOUNT * 3);

        // Simulate yield
        uint256 yieldAmount = DEPOSIT_AMOUNT; // Add 1000 USDC yield
        vm.prank(OWNER);
        vault.simulateYield(yieldAmount);

        uint256 totalAfterYield = bridgeBank.totalVaultAssets();
        assertEq(totalAfterYield, DEPOSIT_AMOUNT * 3 + yieldAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CannotRefundAfterMint() public {
        // Deposit
        (uint256 nonce, uint256 shares) = _deposit(DEPOSIT_AMOUNT);

        // Mint on destination
        (BridgeTypes.BridgeMessage memory message, bytes memory signature) =
            _createAndSignMessage(nonce, DEPOSIT_AMOUNT, shares, block.timestamp + 1 hours);
        destBridge.mint(message, signature);

        // Mark completed
        vm.prank(OWNER);
        bridgeBank.markCompleted(nonce);

        // Try to refund - should fail
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, nonce));
        bridgeBank.refund(nonce, 0);
    }

    function test_CannotMintTwice() public {
        (uint256 nonce, uint256 shares) = _deposit(DEPOSIT_AMOUNT);

        (BridgeTypes.BridgeMessage memory message, bytes memory signature) =
            _createAndSignMessage(nonce, DEPOSIT_AMOUNT, shares, block.timestamp + 1 hours);

        // First mint succeeds
        destBridge.mint(message, signature);

        // Second mint fails
        vm.expectRevert(abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, nonce));
        destBridge.mint(message, signature);
    }
}
