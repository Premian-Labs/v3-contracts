// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {UD50x28, ud50x28} from "contracts/libraries/UD50x28.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryDeployer} from "contracts/factory/PoolFactoryDeployer.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";

import {IPoolMock} from "./pool/mock/IPoolMock.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolCoreMock} from "./pool/mock/PoolCoreMock.sol";
import {PoolDepositWithdraw} from "contracts/pool/PoolDepositWithdraw.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {Premia} from "contracts/proxy/Premia.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ERC20Router} from "contracts/router/ERC20Router.sol";

import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";

import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {OracleAdapterMock} from "./adapter/OracleAdapterMock.sol";
import {FlashLoanMock} from "./pool/mock/FlashLoanMock.sol";
import {ReferralMock} from "./referral/ReferralMock.sol";
import {IReferralMock} from "./referral/IReferralMock.sol";

import {ExchangeHelper} from "contracts/utils/ExchangeHelper.sol";
import {Placeholder} from "contracts/utils/Placeholder.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {UserSettings} from "contracts/settings/UserSettings.sol";

import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";

import {Assertions} from "./Assertions.sol";

contract DeployTest is Test, Assertions {
    uint256 mainnetFork;

    UD60x18 settlementPrice;

    address base;
    address quote;
    IERC20 premia;

    bool isCallTest;

    OracleAdapterMock oracleAdapter;
    IPoolFactory.PoolKey poolKey;
    PoolFactory factory;
    Premia diamond;
    ERC20Router router;
    ExchangeHelper exchangeHelper;
    IReferralMock referral;
    IUserSettings userSettings;
    IVxPremia vxPremia;
    VaultRegistry vaultRegistry;

    IPoolMock pool;

    Position.Key posKey;

    IPoolInternal.QuoteOB quoteOB;

    Users users;

    FlashLoanMock flashLoanMock;

    struct Users {
        address lp;
        address otherLP;
        address trader;
        address otherTrader;
        address referrer;
        address operator;
        address caller;
        address receiver;
        address underwriter;
    }

    bytes4[] internal poolBaseSelectors;
    bytes4[] internal poolCoreMockSelectors;
    bytes4[] internal poolCoreSelectors;
    bytes4[] internal poolDepositWithdrawSelectors;
    bytes4[] internal poolTradeSelectors;

    address public constant FEE_RECEIVER = address(123456789);

    receive() external payable {}

    function setUp() public virtual {
        _setUp(17100000, 1682668800);
    }

    function _setUp(uint256 forkBlock, uint256 maturity) internal {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL, forkBlock);
        vm.selectFork(mainnetFork);

        users = Users({
            lp: vm.addr(1),
            otherLP: vm.addr(2),
            trader: vm.addr(3),
            otherTrader: vm.addr(4),
            referrer: vm.addr(5),
            operator: vm.addr(6),
            caller: vm.addr(7),
            receiver: vm.addr(8),
            underwriter: vm.addr(9)
        });

        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        quote = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        premia = IERC20(0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70);

        settlementPrice = ud(1000 ether);
        oracleAdapter = new OracleAdapterMock(address(base), address(quote), settlementPrice, settlementPrice);

        poolKey = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });

        quoteOB = IPoolInternal.QuoteOB({
            provider: users.lp,
            taker: address(0),
            price: ud(0.1e18),
            size: ud(10 ether),
            isBuy: false,
            deadline: block.timestamp + 1 hours,
            salt: block.timestamp
        });

        diamond = new Premia();

        Placeholder placeholder = new Placeholder();
        PoolFactoryProxy factoryProxy = new PoolFactoryProxy(address(placeholder));

        PoolFactoryDeployer poolFactoryDeployer = new PoolFactoryDeployer(address(diamond), address(factoryProxy));
        PoolFactory factoryImpl = new PoolFactory(address(diamond), address(poolFactoryDeployer));
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
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_depositFeeAndTicksUpdate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_getStrandedMarketPriceUpdate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_getTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_isMarketPriceStranded.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_mint.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_isRateNonTerminating.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_roundDown.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_roundDownUD60x18.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_roundDownSD59x18.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_roundUp.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.exposed_roundUpUD60x18.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getCurrentTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getGlobalFeeRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getLiquidityRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getLongRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.getPositionFeeRate.selector);
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

        ///////////////////////

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.1 ether),
            upper: ud(0.3 ether),
            orderType: Position.OrderType.LC
        });
    }

    function deposit(uint256 depositSize) internal returns (uint256 initialCollateral) {
        return deposit(ud(depositSize));
    }

    function deposit(UD60x18 depositSize) internal returns (uint256 initialCollateral) {
        return deposit(pool, posKey, poolKey.strike, depositSize, Position.isLong(posKey.orderType));
    }

    function deposit(
        Position.Key memory customPosKey,
        uint256 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(pool, customPosKey, poolKey.strike, ud(depositSize), Position.isLong(customPosKey.orderType));
    }

    function deposit(
        Position.Key memory customPosKey,
        UD60x18 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(pool, customPosKey, poolKey.strike, depositSize, Position.isLong(customPosKey.orderType));
    }

    function deposit(
        IPoolMock _pool,
        UD60x18 strike,
        UD60x18 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(_pool, posKey, strike, depositSize, Position.isLong(posKey.orderType));
    }

    function deposit(
        uint256 depositSize,
        bool isBidIfStrandedMarketPrice
    ) internal returns (uint256 initialCollateral) {
        return deposit(pool, posKey, poolKey.strike, ud(depositSize), isBidIfStrandedMarketPrice);
    }

    function deposit(
        UD60x18 depositSize,
        bool isBidIfStrandedMarketPrice
    ) internal returns (uint256 initialCollateral) {
        return deposit(pool, posKey, poolKey.strike, depositSize, isBidIfStrandedMarketPrice);
    }

    function deposit(
        IPoolMock _pool,
        Position.Key memory customPosKey,
        UD60x18 strike,
        UD60x18 depositSize,
        bool isBidIfStrandedMarketPrice
    ) internal returns (uint256 initialCollateral) {
        IERC20 token = IERC20(getPoolToken());
        initialCollateral = toTokenDecimals(isCallTest ? depositSize : depositSize * strike);

        vm.startPrank(customPosKey.operator);

        deal(address(token), customPosKey.operator, initialCollateral);
        token.approve(address(router), initialCollateral);

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = _pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );

        _pool.deposit(
            customPosKey,
            nearestBelowLower,
            nearestBelowUpper,
            depositSize,
            ZERO,
            ONE,
            isBidIfStrandedMarketPrice
        );

        vm.stopPrank();
    }

    function tradeOnly(uint256 tradeSize, bool isBuy) internal returns (uint256 totalPremium) {
        UD60x18 _tradeSize = ud(tradeSize);
        (totalPremium, ) = pool.getQuoteAMM(users.trader, _tradeSize, isBuy);
        deal(getPoolToken(), users.trader, tradeSize);
        vm.startPrank(users.trader);
        IERC20(getPoolToken()).approve(address(router), tradeSize);
        pool.trade(
            _tradeSize,
            isBuy,
            isBuy ? totalPremium + totalPremium / 10 : totalPremium - totalPremium / 10,
            address(0)
        );
        vm.stopPrank();
    }

    function trade(uint256 tradeSize, bool isBuy) internal returns (uint256 initialCollateral, uint256 totalPremium) {
        (initialCollateral, totalPremium) = trade(tradeSize, isBuy, tradeSize, false);
    }

    function trade(
        uint256 tradeSize,
        bool isBuy,
        uint256 depositSize
    ) internal returns (uint256 initialCollateral, uint256 totalPremium) {
        (initialCollateral, totalPremium) = trade(tradeSize, isBuy, depositSize, false);
    }

    function trade(
        uint256 tradeSize,
        bool isBuy,
        uint256 depositSize,
        bool isCSUP
    ) internal returns (uint256 initialCollateral, uint256 totalPremium) {
        if (isBuy && isCSUP) posKey.orderType = Position.OrderType.CSUP;
        if (isBuy && !isCSUP) posKey.orderType = Position.OrderType.CS;

        initialCollateral = deposit(posKey, depositSize);

        UD60x18 _tradeSize = ud(tradeSize);

        (totalPremium, ) = pool.getQuoteAMM(users.trader, _tradeSize, isBuy);

        address poolToken = getPoolToken();

        uint256 mintAmount = isBuy ? totalPremium : toTokenDecimals(poolKey.strike);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, mintAmount);
        IERC20(poolToken).approve(address(router), mintAmount);

        pool.trade(
            _tradeSize,
            isBuy,
            isBuy ? totalPremium + totalPremium / 10 : totalPremium - totalPremium / 10,
            address(0)
        );
        vm.stopPrank();
    }

    function getPoolToken() internal view returns (address) {
        return isCallTest ? base : quote;
    }

    function contractsToCollateral(UD60x18 amount) internal view returns (UD60x18) {
        return isCallTest ? amount : amount * poolKey.strike;
    }

    function collateralToContracts(UD60x18 amount) internal view returns (UD60x18) {
        return isCallTest ? amount : amount / poolKey.strike;
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function toTokenDecimals(UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function roundUpToTokenDecimals(UD60x18 amount) internal view returns (uint256) {
        UD60x18 amountRoundedDown = fromTokenDecimals(toTokenDecimals(amount));
        if (amountRoundedDown != amount) {
            return toTokenDecimals(amount) + uint256(1);
        } else {
            return toTokenDecimals(amount);
        }
    }

    function truncate(UD60x18 amount) internal view returns (UD60x18) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return OptionMath.truncate(amount, decimals);
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), decimals, 18);
    }

    function tokenId() internal view returns (uint256) {
        return PoolStorage.formatTokenId(posKey.operator, posKey.lower, posKey.upper, posKey.orderType);
    }

    function getSettlementPrice(bool isITM) internal view returns (UD60x18) {
        if (isCallTest) {
            return isITM ? UD60x18.wrap(1200 ether) : UD60x18.wrap(800 ether);
        } else {
            return isITM ? UD60x18.wrap(800 ether) : UD60x18.wrap(1200 ether);
        }
    }

    function getExerciseValue(
        bool isITM,
        UD60x18 tradeSize,
        UD60x18 _settlementPrice
    ) internal view returns (UD60x18 exerciseValue) {
        if (isITM) {
            if (isCallTest) {
                exerciseValue = tradeSize * (_settlementPrice - poolKey.strike);
                exerciseValue = exerciseValue / _settlementPrice;
            } else {
                exerciseValue = tradeSize * (poolKey.strike - _settlementPrice);
            }
        }

        return exerciseValue;
    }

    function getCollateralValue(UD60x18 tradeSize, UD60x18 exerciseValue) internal view returns (UD60x18) {
        return isCallTest ? tradeSize - exerciseValue : tradeSize * poolKey.strike - exerciseValue;
    }

    function setActionAuthorization(address user, IUserSettings.Action action, bool authorization) internal {
        IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
        actions[0] = action;

        bool[] memory _authorization = new bool[](1);
        _authorization[0] = authorization;

        vm.prank(user);
        userSettings.setActionAuthorization(users.operator, actions, _authorization);
    }

    function enableExerciseSettleAuthorization(address user, UD60x18 authorizedCost) internal {
        IUserSettings.Action[] memory actions = new IUserSettings.Action[](3);
        actions[0] = IUserSettings.Action.Exercise;
        actions[1] = IUserSettings.Action.Settle;
        actions[2] = IUserSettings.Action.SettlePosition;

        bool[] memory authorization = new bool[](3);
        authorization[0] = true;
        authorization[1] = true;
        authorization[2] = true;

        vm.startPrank(user);
        userSettings.setActionAuthorization(users.operator, actions, authorization);
        userSettings.setAuthorizedCost(authorizedCost);
        vm.stopPrank();
    }
}
