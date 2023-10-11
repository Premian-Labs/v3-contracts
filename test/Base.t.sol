// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {Test} from "forge-std/Test.sol";

import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryDeployer} from "contracts/factory/PoolFactoryDeployer.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";

import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolCoreMock} from "contracts/test/pool/PoolCoreMock.sol";
import {PoolDepositWithdraw} from "contracts/pool/PoolDepositWithdraw.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";

import {Premia} from "contracts/proxy/Premia.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ERC20Router} from "contracts/router/ERC20Router.sol";
import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";

import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {OracleAdapterMock} from "contracts/test/adapter/OracleAdapterMock.sol";
import {FlashLoanMock} from "contracts/test/pool/FlashLoanMock.sol";
import {ReferralMock} from "contracts/test/referral/ReferralMock.sol";
import {IReferralMock} from "contracts/test/referral/IReferralMock.sol";

import {ExchangeHelper} from "contracts/utils/ExchangeHelper.sol";
import {Placeholder} from "contracts/utils/Placeholder.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {UserSettings} from "contracts/settings/UserSettings.sol";

import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";

import {Assertions} from "./utils/Assertions.sol";
import {Constants} from "./utils/Constants.sol";
import {Defaults} from "./utils/Defaults.sol";
import {Fuzzers} from "./utils/Fuzzers.sol";
import {Users} from "./utils/Types.sol";
import {Utils} from "./utils/Utils.sol";

/// @notice Base test contract with common logic needed by all tests.
/// @dev Inspired from https://github.com/sablier-labs/v2-core/blob/main/test/Base.t.sol
abstract contract Base_Test is Test, Assertions, Constants, Utils, Fuzzers {
    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/
    string internal ctxMsg = "";
    Users internal users;
    uint256 internal mainnetFork;

    bytes4[] internal poolBaseSelectors;
    bytes4[] internal poolCoreMockSelectors;
    bytes4[] internal poolCoreSelectors;
    bytes4[] internal poolDepositWithdrawSelectors;
    bytes4[] internal poolTradeSelectors;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/
    ERC20Mock internal base;
    ERC20Mock internal quote;
    ERC20Mock internal premia;
    Defaults internal defaults;

    OracleAdapterMock internal oracleAdapter;
    PoolFactory internal factory;
    Premia internal diamond;
    ERC20Router internal router;
    ExchangeHelper internal exchangeHelper;
    IReferralMock internal referral;
    IUserSettings internal userSettings;
    IVxPremia internal vxPremia;
    VaultRegistry internal vaultRegistry;
    FlashLoanMock internal flashLoanMock;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // If this is a fork test then, fork before deploying contracts
        if (isForkTest()) {
            vm.createSelectFork({blockNumber: getStartBlock(), urlOrAlias: getNetwork()});
        }

        // Deploy the base test contracts.
        base = new ERC20Mock("BASE", 18);
        quote = new ERC20Mock("QUOTE", 6);
        premia = new ERC20Mock("PREMIA", 18);

        // Label the base test contracts.
        vm.label({account: address(base), newLabel: "BASE"});
        vm.label({account: address(quote), newLabel: "QUOTE"});
        vm.label({account: address(premia), newLabel: "PREMIA"});

        // Create users for testing.
        users = Users({
            deployer: createUser("Deployer"),
            admin: createUser("Admin"),
            alice: createUser("Alice"),
            bob: createUser("Bob"),
            charles: createUser("Charles"),
            eve: createUser("Eve"),
            trader: createUser("Trader"),
            lp: createUser("LP"),
            referrer: createUser("Referrer"),
            operator: createUser("Operator"),
            caller: createUser("Caller"),
            receiver: createUser("Receiver"),
            underwriter: createUser("Underwriter"),
            broke: payable(makeAddr("Broke")),
            relayer: createUser("Relayer")
        });

        // Deploy the defaults contract.
        defaults = new Defaults();
        defaults.setBase(IERC20(address(base)));
        defaults.setQuote(IERC20(address(quote)));
        defaults.setUsers(users);

        vm.warp(getStartTimestamp());

        // Deploy the contracts
        vm.startPrank(users.deployer);
        deploy();

        // Label contracts
        label();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    modifier logContext() {
        _;

        if (failed()) {
            emit log(ctxMsg);
        }
    }

    // @dev Whether or not the test is a fork test.
    function isForkTest() internal virtual returns (bool) {
        return false;
    }

    /// @dev Gets the network to fork.
    function getNetwork() internal virtual returns (string memory) {
        return "mainnet";
    }

    // @dev Gets the starting block for the fork test.
    function getStartBlock() internal virtual returns (uint256) {
        return 16_126_000;
    }

    /// @dev Gets the start timestamp for the test.
    function getStartTimestamp() internal virtual returns (uint256) {
        // Warp to May 1, 2023 at 00:00 GMT to provide a more realistic testing environment.
        return MAY_1_2023;
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal(user, 100 ether);
        deal({token: address(base), to: user, give: 1_000_000_000e18});
        deal({token: address(quote), to: user, give: 1_000_000_000e18});
        return user;
    }

    /// @dev Deploys the V3 Core contracts.
    function deploy() internal virtual {
        UD60x18 settlementPrice = ud(1000 ether);
        oracleAdapter = new OracleAdapterMock(address(base), address(quote), settlementPrice, settlementPrice);

        diamond = new Premia();

        Placeholder placeholder = new Placeholder();
        PoolFactoryProxy factoryProxy = new PoolFactoryProxy(address(placeholder), ud(0.1 ether), FEE_RECEIVER);

        PoolFactoryDeployer poolFactoryDeployer = new PoolFactoryDeployer(address(diamond), address(factoryProxy));
        PoolFactory factoryImpl = new PoolFactory(
            address(diamond),
            address(oracleAdapter),
            address(base),
            address(poolFactoryDeployer)
        );
        factoryProxy.setImplementation(address(factoryImpl));

        flashLoanMock = new FlashLoanMock();

        factory = PoolFactory(address(factoryProxy));
        router = new ERC20Router(address(factory));

        ReferralMock referralImpl = new ReferralMock(address(factory));
        ReferralProxy referralProxy = new ReferralProxy(address(referralImpl));
        referral = IReferralMock(address(referralProxy));

        UserSettings userSettingsImpl = new UserSettings();

        ProxyUpgradeableOwnable userSettingsProxy = new ProxyUpgradeableOwnable(address(userSettingsImpl));

        userSettings = IUserSettings(address(userSettingsProxy));

        address vaultRegistryImpl = address(new VaultRegistry());
        address vaultRegistryProxy = address(new ProxyUpgradeableOwnable(vaultRegistryImpl));
        vaultRegistry = VaultRegistry(vaultRegistryProxy);

        VxPremia vxPremiaImpl = new VxPremia(
            address(0),
            address(0),
            address(premia),
            address(quote),
            address(exchangeHelper),
            vaultRegistryProxy
        );

        VxPremiaProxy vxPremiaProxy = new VxPremiaProxy(address(vxPremiaImpl));

        vxPremia = IVxPremia(address(vxPremiaProxy));

        PoolBase poolBaseImpl = new PoolBase();

        PoolCoreMock poolCoreMockImpl = new PoolCoreMock(
            address(factory),
            address(router),
            address(base),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        PoolCore poolCoreImpl = new PoolCore(
            address(factory),
            address(router),
            address(base),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        PoolDepositWithdraw poolDepositWithdrawImpl = new PoolDepositWithdraw(
            address(factory),
            address(router),
            address(base),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        PoolTrade poolTradeImpl = new PoolTrade(
            address(factory),
            address(router),
            address(base),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        /////////////////////
        // Register facets //
        /////////////////////

        // PoolBase
        poolBaseSelectors.push(poolBaseImpl.accountsByToken.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOf.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOfBatch.selector);
        poolBaseSelectors.push(poolBaseImpl.isApprovedForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.name.selector);
        poolBaseSelectors.push(poolBaseImpl.safeBatchTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.safeTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.setApprovalForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.tokensByAccount.selector);
        poolBaseSelectors.push(poolBaseImpl.totalHolders.selector);
        poolBaseSelectors.push(poolBaseImpl.totalSupply.selector);

        // PoolCoreMock
        poolCoreMockSelectors.push(poolCoreMockImpl._getPricing.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_getStrandedArea.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_cross.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_getStrandedMarketPriceUpdate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_getTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_isMarketPriceStranded.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_mint.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_isRateNonTerminating.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getCurrentTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getLiquidityRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getLongRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getShortRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.formatTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.quoteOBHash.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.parseTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.protocolFees.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exerciseFee.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.mint.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getPositionData.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.forceUpdateClaimableFees.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.forceUpdateLastDeposit.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.safeTransferIgnoreDust.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.safeTransferIgnoreDustUD60x18.selector);

        // PoolCore
        poolCoreSelectors.push(poolCoreImpl.annihilate.selector);
        poolCoreSelectors.push(poolCoreImpl.annihilateFor.selector);
        poolCoreSelectors.push(poolCoreImpl.claim.selector);
        poolCoreSelectors.push(poolCoreImpl.exercise.selector);
        poolCoreSelectors.push(poolCoreImpl.exerciseFor.selector);
        poolCoreSelectors.push(poolCoreImpl.getClaimableFees.selector);
        poolCoreSelectors.push(poolCoreImpl.getPoolSettings.selector);
        poolCoreSelectors.push(poolCoreImpl.getSettlementPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.getTokenIds.selector);
        poolCoreSelectors.push(poolCoreImpl.marketPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.settle.selector);
        poolCoreSelectors.push(poolCoreImpl.settleFor.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePosition.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePositionFor.selector);
        poolCoreSelectors.push(poolCoreImpl.takerFee.selector);
        poolCoreSelectors.push(poolCoreImpl._takerFeeLowLevel.selector);
        poolCoreSelectors.push(poolCoreImpl.transferPosition.selector);
        poolCoreSelectors.push(poolCoreImpl.tryCacheSettlementPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.writeFrom.selector);
        poolCoreSelectors.push(poolCoreImpl.ticks.selector);

        // PoolDepositWithdraw
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256("deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256)")
            )
        );
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,bool)"
                )
            )
        );
        poolDepositWithdrawSelectors.push(poolDepositWithdrawImpl.withdraw.selector);
        poolDepositWithdrawSelectors.push(poolDepositWithdrawImpl.getNearestTicksBelow.selector);

        // PoolTrade
        poolTradeSelectors.push(poolTradeImpl.cancelQuotesOB.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuoteOB.selector);
        poolTradeSelectors.push(poolTradeImpl.flashLoan.selector);
        poolTradeSelectors.push(poolTradeImpl.maxFlashLoan.selector);
        poolTradeSelectors.push(poolTradeImpl.flashFee.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteAMM.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteOBFilledAmount.selector);
        poolTradeSelectors.push(poolTradeImpl.isQuoteOBValid.selector);
        poolTradeSelectors.push(poolTradeImpl.trade.selector);

        IDiamondWritableInternal.FacetCut[] memory facetCuts = new IDiamondWritableInternal.FacetCut[](5);

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolBaseImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolBaseSelectors
        );

        facetCuts[1] = IDiamondWritableInternal.FacetCut(
            address(poolCoreMockImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreMockSelectors
        );

        facetCuts[2] = IDiamondWritableInternal.FacetCut(
            address(poolCoreImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreSelectors
        );

        facetCuts[3] = IDiamondWritableInternal.FacetCut(
            address(poolDepositWithdrawImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolDepositWithdrawSelectors
        );

        facetCuts[4] = IDiamondWritableInternal.FacetCut(
            address(poolTradeImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolTradeSelectors
        );

        diamond.diamondCut(facetCuts, address(0), "");
    }

    /// @dev Labels the deployed contracts.
    function label() internal virtual {
        // Label contracts
        vm.label({account: address(oracleAdapter), newLabel: "OracleAdapter"});
        vm.label({account: address(factory), newLabel: "PoolFactory"});
        vm.label({account: address(diamond), newLabel: "Premia"});
        vm.label({account: address(router), newLabel: "Router"});
        vm.label({account: address(exchangeHelper), newLabel: "ExchangeHelper"});
        vm.label({account: address(referral), newLabel: "Referral"});
        vm.label({account: address(userSettings), newLabel: "UserSettings"});
        vm.label({account: address(vxPremia), newLabel: "VxPremia"});
        vm.label({account: address(vaultRegistry), newLabel: "VaultRegistry"});
        vm.label({account: address(flashLoanMock), newLabel: "FlashLoan"});
    }

    /// @dev Approves a contract to spend base and quote for a user.
    function approveContract(address contractAddress) internal {
        base.approve({spender: contractAddress, amount: MAX_UINT256});
        quote.approve({spender: contractAddress, amount: MAX_UINT256});
    }

    /// @dev Approves all core contracts to spend base and quote from a user.
    function approveProtocolForUser(address user) internal {
        changePrank({msgSender: user});
        approveContract(address(router));
        approveContract(address(referral));
    }

    /// @dev Approves all core contracts to spend base and quote from select users.
    function approve() internal virtual {
        // Approve protocol for users
        approveProtocolForUser(users.alice);
        approveProtocolForUser(users.eve);
        approveProtocolForUser(users.trader);
        approveProtocolForUser(users.lp);
        approveProtocolForUser(users.operator);
        approveProtocolForUser(users.caller);
        approveProtocolForUser(users.receiver);

        // Finally, change the active prank back to the Admin.
        changePrank({msgSender: users.admin});
    }
}
