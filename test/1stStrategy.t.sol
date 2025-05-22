// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract VaultTest is Test {
    StMNT public vault;

    Strategy1st public strategy1st;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));
    // Mantle WMNT mainet

    function setUp() public {
        vault = new StMNT();
    }

    function wrapMNT(uint256 _amount) internal {
        WMNT.deposit{value: _amount}();
    }

    /**
     * @notice Tests correct initialization of the Vault contract.
     * - Ensures that all roles (governance, management, guardian, treasury) are assigned correctly.
     * - Validates the default parameters (fees, degradation rate, token metadata).
     * - Verifies the deposit limit is correctly settable by governance.
     * - Reverts on re-initialization and unauthorized access to fee configuration.
     */
    function testInitialize() internal {
        vm.startPrank(governance);
        vault.initialize(
            address(WMNT),
            governance,
            treasury,
            "stMNT",
            "stMNT",
            guardian,
            management
        );
        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "stMNT");
        assertEq(vault.symbol(), "stMNT");
        assertEq(address(vault.token()), address(WMNT));

        assertEq(vault.performanceFee(), 1_000);
        assertEq(vault.managementFee(), 200);
        assertEq(vault.lockedProfitDegradation(), 46000000000000);

        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(1_000_000 ether);

        assertEq(vault.depositLimit(), 1_000_000 ether);
        assertEq(vault.performanceFee(), 0);
        assertEq(vault.managementFee(), 0);

        vm.expectRevert();
        vault.initialize(
            address(WMNT),
            governance,
            treasury,
            "Staked Mantle Vault",
            "sMNT",
            guardian,
            management
        );
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(1000);
        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(1000);
        vm.stopPrank();
    }

    /**
     * @notice Tests a single user's full deposit and withdrawal lifecycle.
     * - User deposits 1000 tokens and receives 1000 shares.
     * - Verifies that pricePerShare remains 1e18 (no strategy).
     * - Withdraws all shares and receives original amount.
     * - Attempting a second withdrawal reverts (no remaining shares).
     */
    function testDepositAndWithdraw() internal {
        vm.deal(user1, 2_000 ether);
        vm.startPrank(user1);
        assertEq(user1.balance, 2_000 ether);
        wrapMNT(1_000 ether);
        WMNT.approve(address(vault), 1000 ether);
        uint256 shares = vault.deposit(1000 ether, user1);
        assertEq(shares, 1000 ether);
        assertEq(vault.pricePerShare(), 1 ether);
        vault.approve(address(vault), 1 ether);
        uint256 assets = vault.withdraw(shares, user1, 100);
        assertEq(assets, 1000 ether);

        vault.approve(address(vault), 1 ether);
        vm.expectRevert();
        vault.withdraw(shares, user1, 100);
        vm.stopPrank();
    }

    //*test inizialize strategiest

    function setUpStrategy() internal {
        strategy1st = new Strategy1st(address(vault), governance);
        vm.startPrank(governance);
        strategy1st.setLendingPool(
            address(0x44949636f778fAD2b139E665aee11a2dc84A2976)
        );
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);
    }

    function setStrategyOnVauls() internal {
        vm.startPrank(governance);
        vault.addStrategy(
            address(strategy1st),
            10_000, //100% di fondi gestiti per ora
            1 ether, // minDebtPerHarvest
            1_000 ether, // maxDebtPerHarvest
            0 // 5% performance fee
        );
        //vault.addStrategyToQueue(address(strategy1st));
        vm.stopPrank();
    }

    function testDepositWithStrategy() internal {
        vm.deal(user1, 2_000 ether);
        vm.startPrank(user1);
        wrapMNT(1_000 ether);
        WMNT.approve(address(vault), 1000 ether);
        uint256 shares = vault.deposit(1000 ether, user1);
        vm.stopPrank();

        vm.startPrank(management); // oppure keeper
        strategy1st.harvest();
        vm.stopPrank();

        /*
        assertEq(shares, 1000 ether);
        assertEq(vault.pricePerShare(), 1 ether);
        vault.approve(address(vault), 1 ether);
        uint256 assets = vault.withdraw(shares, user1, 100);
        assertEq(assets, 1000 ether);

        vault.approve(address(vault), 1 ether);
        vm.expectRevert();
        vault.withdraw(shares, user1, 100);*/
    }

    function testAllTogether() public {
        // ✅ Initializes the Vault and verifies core parameters
        testInitialize();

        setUpStrategy();

        setStrategyOnVauls();

        testDepositWithStrategy();


    }
}
