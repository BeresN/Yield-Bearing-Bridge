// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {BridgeBank} from "../../src/source/BridgeBank.sol";
import {BridgeTypes} from "../../src/libraries/BridgeTypes.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockERC4626} from "../../src/mocks/MockERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title BridgeBankTest
 * @notice Unit tests for BridgeBank contract
 */
contract BridgeBankTest is Test {
    BridgeBank public bridgeBank;
    MockERC20 public usdc;
    MockERC4626 public vault;

    address constant OWNER = address(1);
    address constant USER = address(2);
    address constant RECIPIENT = address(3);

    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    uint256 constant DEPOSIT_AMOUNT = 1000e6;
    uint256 constant DESTINATION_CHAIN_ID = 137;

    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC");
        vault = new MockERC4626(ERC20(address(usdc)), "Vault USDC", "vUSDC");

        // Deploy BridgeBank
        bridgeBank = new BridgeBank(address(vault), OWNER);

        vm.stopPrank();

        // Fund user with USDC
        usdc.mint(USER, INITIAL_BALANCE);

        // Label addresses for traces
        vm.label(address(usdc), "USDC");
        vm.label(address(vault), "Vault");
        vm.label(address(bridgeBank), "BridgeBank");
        vm.label(OWNER, "Owner");
        vm.label(USER, "User");
        vm.label(RECIPIENT, "Recipient");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        vm.expectEmit(true, true, true, true);
        emit BridgeTypes.Deposited(
            USER,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            DEPOSIT_AMOUNT,
            1,
            DESTINATION_CHAIN_ID
        );

        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        assertEq(nonce, 1);
        assertEq(usdc.balanceOf(USER), INITIAL_BALANCE - DEPOSIT_AMOUNT);
        assertEq(bridgeBank.depositNonce(), 1);
    }

    function test_DepositRecordCreation() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);

        assertEq(record.depositor, USER);
        assertEq(record.recipient, RECIPIENT);
        assertEq(record.amount, DEPOSIT_AMOUNT);
        assertEq(record.shares, DEPOSIT_AMOUNT); // 1:1 in mock vault initially
        assertEq(record.nonce, nonce);
        assertEq(record.sourceChainId, block.chainid);
        assertEq(record.destinationChainId, DESTINATION_CHAIN_ID);
        assertEq(
            uint8(record.status),
            uint8(BridgeTypes.DepositStatus.Pending)
        );
    }

    function test_MultipleDeposits() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT * 3);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        uint256 nonce1 = bridgeBank.deposit(params);
        uint256 nonce2 = bridgeBank.deposit(params);
        uint256 nonce3 = bridgeBank.deposit(params);
        vm.stopPrank();

        assertEq(nonce1, 1);
        assertEq(nonce2, 2);
        assertEq(nonce3, 3);
        assertEq(bridgeBank.depositNonce(), 3);
    }

    function test_RevertWhen_ZeroAmount() public {
        vm.startPrank(USER);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: 0,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        vm.expectRevert(BridgeTypes.ZeroAmount.selector);
        bridgeBank.deposit(params);
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroRecipient() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: address(0),
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        vm.expectRevert(BridgeTypes.ZeroAddress.selector);
        bridgeBank.deposit(params);
        vm.stopPrank();
    }

    function test_RevertWhen_Paused() public {
        vm.prank(OWNER);
        bridgeBank.pause();

        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);

        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });

        vm.expectRevert();
        bridgeBank.deposit(params);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Refund() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        uint256 userBalanceBefore = usdc.balanceOf(USER);

        // Owner refunds
        vm.prank(OWNER);
        bridgeBank.refund(nonce);

        assertEq(usdc.balanceOf(USER), userBalanceBefore + DEPOSIT_AMOUNT);

        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);
        assertEq(
            uint8(record.status),
            uint8(BridgeTypes.DepositStatus.Refunded)
        );
    }

    function test_RefundWithYield() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Simulate yield accrual (10% yield)
        // Minting to vault increases totalAssets and thus share value
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10;
        usdc.mint(address(vault), yieldAmount);

        uint256 userBalanceBefore = usdc.balanceOf(USER);

        // Owner refunds - should include yield
        vm.prank(OWNER);
        bridgeBank.refund(nonce);

        // User should receive more than original deposit due to yield
        assertGt(usdc.balanceOf(USER), userBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test_RevertWhen_RefundNonOwner() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Non-owner tries to refund
        vm.prank(USER);
        vm.expectRevert();
        bridgeBank.refund(nonce);
    }

    function test_RevertWhen_RefundAlreadyCompleted() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Mark as completed
        vm.prank(OWNER);
        bridgeBank.markCompleted(nonce);

        // Try to refund completed deposit
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, nonce)
        );
        bridgeBank.refund(nonce);
    }

    function test_RevertWhen_RefundAlreadyRefunded() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // First refund
        vm.prank(OWNER);
        bridgeBank.refund(nonce);

        // Try to refund again
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, nonce)
        );
        bridgeBank.refund(nonce);
    }

    /*//////////////////////////////////////////////////////////////
                        MARK COMPLETED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MarkCompleted() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Mark as completed
        vm.prank(OWNER);
        bridgeBank.markCompleted(nonce);

        BridgeTypes.DepositRecord memory record = bridgeBank.getDeposit(nonce);
        assertEq(
            uint8(record.status),
            uint8(BridgeTypes.DepositStatus.Completed)
        );
    }

    function test_RevertWhen_MarkCompletedNonOwner() public {
        // First deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        // Non-owner tries to mark completed
        vm.prank(USER);
        vm.expectRevert();
        bridgeBank.markCompleted(nonce);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetDepositValue() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        uint256 value = bridgeBank.getDepositValue(nonce);
        assertEq(value, DEPOSIT_AMOUNT);

        // Simulate yield
        vm.prank(OWNER);
        vault.simulateYield(DEPOSIT_AMOUNT / 10);

        uint256 valueWithYield = bridgeBank.getDepositValue(nonce);
        assertGt(valueWithYield, DEPOSIT_AMOUNT);
    }

    function test_TotalVaultAssets() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        bridgeBank.deposit(params);
        vm.stopPrank();

        assertEq(bridgeBank.totalVaultAssets(), DEPOSIT_AMOUNT);
    }

    function test_TotalVaultShares() public {
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        bridgeBank.deposit(params);
        vm.stopPrank();

        assertEq(bridgeBank.totalVaultShares(), DEPOSIT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause() public {
        vm.prank(OWNER);
        bridgeBank.pause();

        // Verify paused by trying to deposit
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        vm.expectRevert();
        bridgeBank.deposit(params);
        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.prank(OWNER);
        bridgeBank.pause();

        vm.prank(OWNER);
        bridgeBank.unpause();

        // Verify unpaused by depositing
        vm.startPrank(USER);
        usdc.approve(address(bridgeBank), DEPOSIT_AMOUNT);
        BridgeTypes.DepositParams memory params = BridgeTypes.DepositParams({
            recipient: RECIPIENT,
            amount: DEPOSIT_AMOUNT,
            destinationChainId: DESTINATION_CHAIN_ID
        });
        uint256 nonce = bridgeBank.deposit(params);
        vm.stopPrank();

        assertEq(nonce, 1);
    }

    function test_RevertWhen_PauseNonOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        bridgeBank.pause();
    }

    function test_RevertWhen_UnpauseNonOwner() public {
        vm.prank(OWNER);
        bridgeBank.pause();

        vm.prank(USER);
        vm.expectRevert();
        bridgeBank.unpause();
    }
}
