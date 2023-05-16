// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {Test} from "forge-std/Test.sol";

import "forge-std/console2.sol";
import "../Addresses.sol";
import {Assertions} from "../Assertions.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IUniswapV3Adapter} from "contracts/adapter/uniswap/IUniswapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/adapter/uniswap/UniswapV3Adapter.sol";
import {UniswapV3AdapterProxy} from "contracts/adapter/uniswap/UniswapV3AdapterProxy.sol";

contract UniswapV3AdapterTest is Test, Assertions {
    uint32 constant PERIOD = 600;
    uint256 constant CARDINALITY_PER_MINUTE = 4;
    IUniswapV3Factory constant UNISWAP_V3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct Pool {
        address tokenIn;
        address tokenOut;
    }

    Pool[] pools;
    UniswapV3Adapter adapter;

    uint256 mainnetFork;
    uint256 target;

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL, 16597500);
        vm.selectFork(mainnetFork);

        target = 1676016000;

        pools.push(Pool(WETH, WBTC));
        pools.push(Pool(WBTC, WETH));
        pools.push(Pool(WBTC, USDC));
        pools.push(Pool(WBTC, USDT));
        pools.push(Pool(WETH, USDT));
        pools.push(Pool(USDT, WETH));
        pools.push(Pool(WETH, DAI));
        pools.push(Pool(MKR, USDC));
        pools.push(Pool(BOND, WETH));
        pools.push(Pool(USDT, USDC));
        pools.push(Pool(DAI, USDC));
        pools.push(Pool(FXS, FRAX));
        pools.push(Pool(FRAX, FXS));
        pools.push(Pool(FRAX, USDT));
        pools.push(Pool(UNI, USDT));
        pools.push(Pool(LINK, UNI));
        pools.push(Pool(MATIC, WETH));
        pools.push(Pool(MATIC, USDC));
        pools.push(Pool(DAI, USDT));

        address implementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );
        address proxy = address(
            new UniswapV3AdapterProxy(
                PERIOD,
                CARDINALITY_PER_MINUTE,
                implementation
            )
        );
        adapter = UniswapV3Adapter(proxy);
    }

    function test_constructor_ShouldSetStateVariables() public {
        assertEq(
            adapter.getTargetCardinality(),
            (PERIOD * CARDINALITY_PER_MINUTE) / 60 + 1
        );
        assertEq(adapter.getPeriod(), PERIOD);
        assertEq(adapter.getCardinalityPerMinute(), CARDINALITY_PER_MINUTE);

        uint24[] memory feeTiers = adapter.getSupportedFeeTiers();
        assertEq(feeTiers.length, 4);
        assertEq(feeTiers[0], 100);
        assertEq(feeTiers[1], 500);
        assertEq(feeTiers[2], 3000);
        assertEq(feeTiers[3], 10000);
    }

    function test_constructor_RevertIf_CardinalityPerMinuteIsZero() public {
        address implementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );

        vm.expectRevert(
            UniswapV3AdapterProxy
                .UniswapV3AdapterProxy__CardinalityPerMinuteNotSet
                .selector
        );
        new UniswapV3AdapterProxy(PERIOD, 0, implementation);
    }

    function test_constructor_RevertIf_PeriodIsZero() public {
        address implementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );

        vm.expectRevert(
            UniswapV3AdapterProxy.UniswapV3AdapterProxy__PeriodNotSet.selector
        );
        new UniswapV3AdapterProxy(0, CARDINALITY_PER_MINUTE, implementation);
    }

    function test_isPairSupported_ReturnFalse_IfPairIsNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPairDoesNotExist() public {
        (, bool hasPath) = adapter.isPairSupported(WETH, address(0));
        assertFalse(hasPath);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                address(0),
                WETH
            )
        );
        adapter.upsertPair(address(0), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                WBTC,
                address(0)
            )
        );
        adapter.upsertPair(WBTC, address(0));
    }

    //    function test_upsertPair_RevertIf_NotEnoughGasToIncreaseCardinality()
    //        public
    //    {
    //        adapter.setCardinalityPerMinute(200);
    //
    //        vm.expectRevert(
    //            abi.encodeWithSelector(
    //                IUniswapV3Adapter
    //                    .UniswapV3Adapter__ObservationCardinalityTooLow
    //                    .selector,
    //                0,
    //                1
    //            )
    //        );
    //        adapter.upsertPair(WETH, USDC);
    //    }

    function test_upsertPair_NotRevert_IfCalledMultipleTimes_ForSamePair()
        public
    {
        adapter.upsertPair(WETH, WBTC);
        (bool isCached, ) = adapter.isPairSupported(WETH, WBTC);
        assertTrue(isCached);
        adapter.upsertPair(WETH, WBTC);
    }

    function test_quote_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairNotSupported.selector,
                WETH,
                address(0)
            )
        );
        adapter.quote(WETH, address(0));
    }

    function test_quote_RevertIf_PairNotAdded_AndCardinalityMustBeIncreased()
        public
    {
        adapter.setCardinalityPerMinute(200);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3Adapter
                    .UniswapV3Adapter__ObservationCardinalityTooLow
                    .selector,
                1,
                2001
            )
        );
        adapter.quote(WETH, DAI);
    }

    function test_quote_FindPath_IfPairNotAdded() public {
        // must increase cardinality to 41 for pool
        IUniswapV3Pool(0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19)
            .increaseObservationCardinalityNext(41);

        assertGt(adapter.quote(WETH, DAI).unwrap(), 0);
    }

    function test_quote_SkipUninitializedPools_AndProvideQuote_WhenNoPoolsCached()
        public
    {
        address tokenIn = WETH;
        address tokenOut = MKR;

        IUniswapV3Pool(0x886072A44BDd944495eFF38AcE8cE75C1EacDAF6)
            .increaseObservationCardinalityNext(41);

        IUniswapV3Pool(0x3aFdC5e6DfC0B0a507A8e023c9Dce2CAfC310316)
            .increaseObservationCardinalityNext(41);

        IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool(
            tokenIn,
            tokenOut,
            100
        );
        assertGt(adapter.quote(tokenIn, tokenOut).unwrap(), 0);
    }

    function test_quote_SkipUninitializedPools_AndProvideQuote_WhenPoolsAreCached()
        public
    {
        address tokenIn = WETH;
        address tokenOut = MKR;

        adapter.upsertPair(tokenIn, tokenOut);
        assertGt(adapter.quote(tokenIn, tokenOut).unwrap(), 0);

        IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool(
            tokenIn,
            tokenOut,
            100
        );
        assertGt(adapter.quote(tokenIn, tokenOut).unwrap(), 0);

        IUniswapV3Pool(0xd9d92C02a8fd1DdB731381f1351DACA19928E0db).initialize(
            4295128740
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3Adapter
                    .UniswapV3Adapter__ObservationCardinalityTooLow
                    .selector,
                1,
                41
            )
        );
        adapter.quote(tokenIn, tokenOut);

        IUniswapV3Pool(0xd9d92C02a8fd1DdB731381f1351DACA19928E0db)
            .increaseObservationCardinalityNext(41);

        vm.warp(block.timestamp + 600);
        assertGt(adapter.quote(tokenIn, tokenOut).unwrap(), 0);
    }

    function test_quote_ReturnQuote_UsingCorrectDenomination() public {
        address tokenIn = WETH; // 18 decimals
        address tokenOut = DAI; // 18 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        UD60x18 quote = adapter.quote(tokenIn, tokenOut);
        UD60x18 invertedQuote = adapter.quote(tokenOut, tokenIn);
        assertApproxEqAbs(
            quote.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            quote.unwrap() / 10000 // 0.01% tolerance
        );

        //

        tokenIn = WETH; // 18 decimals
        tokenOut = USDT; // 8 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        quote = adapter.quote(tokenIn, tokenOut);
        invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertApproxEqAbs(
            quote.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            quote.unwrap() / 10000 // 0.01% tolerance
        );

        //

        tokenIn = WBTC; // 8 decimals
        tokenOut = USDC; // 6 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        quote = adapter.quote(tokenIn, tokenOut);
        invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertApproxEqAbs(
            quote.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            quote.unwrap() / 10000 // 0.01% tolerance
        );
    }

    function test_poolsForPair_ReturnPoolsForPair() public {
        address[] memory pools = adapter.poolsForPair(WETH, DAI);
        assertEq(pools.length, 0);

        adapter.upsertPair(WETH, DAI);
        pools = adapter.poolsForPair(WETH, DAI);
        assertEq(pools.length, 4);
        assertEq(pools[0], 0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19);
        assertEq(pools[1], 0x60594a405d53811d3BC4766596EFD80fd545A270);
        assertEq(pools[2], 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
        assertEq(pools[3], 0xa80964C5bBd1A0E95777094420555fead1A26c1e);
    }

    function test_getFactory_ReturnExpectedValue() public {
        assertEq(address(adapter.getFactory()), address(UNISWAP_V3_FACTORY));
    }

    function test_getPeriod_ReturnExpectedValue() public {
        assertEq(adapter.getPeriod(), 600);
    }

    function test_getCardinalityPerMinute_ReturnExpectedValue() public {
        assertEq(adapter.getCardinalityPerMinute(), 4);
    }

    function test_getGasPerCardinality_ReturnExpectedValue() public {
        assertEq(adapter.getGasPerCardinality(), 22250);
    }

    function test_getGasToSupportPool_ReturnExpectedValue() public {
        assertEq(adapter.getGasToSupportPool(), 30000);
    }

    function test_getSupportedFeeTiers_ReturnExpectedValue() public {
        uint24[] memory feeTiers = adapter.getSupportedFeeTiers();
        assertEq(feeTiers.length, 4);
        assertEq(feeTiers[0], 100);
        assertEq(feeTiers[1], 500);
        assertEq(feeTiers[2], 3000);
        assertEq(feeTiers[3], 10000);
    }

    function test_setPeriod_SetNewPeriod() public {
        adapter.setPeriod(800);
        assertEq(adapter.getPeriod(), 800);
    }

    function test_setPeriod_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.setPeriod(800);
    }

    function test_setPeriod_RevertIf_NewValueIsZero() public {
        vm.expectRevert(
            IUniswapV3Adapter.UniswapV3Adapter__PeriodNotSet.selector
        );
        adapter.setPeriod(0);
    }

    function test_setPeriod_SetCardinalityPerMinute() public {
        adapter.setCardinalityPerMinute(8);
        assertEq(adapter.getCardinalityPerMinute(), 8);
    }

    function test_setCardinalityPerMinute_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.setCardinalityPerMinute(8);
    }

    function test_setCardinalityPerMinute_RevertIf_NewValueIsZero() public {
        vm.expectRevert(
            IUniswapV3Adapter
                .UniswapV3Adapter__CardinalityPerMinuteNotSet
                .selector
        );
        adapter.setCardinalityPerMinute(0);
    }

    function test_insertFeeTier_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.insertFeeTier(200);
    }

    function test_insertFeeTier_RevertIf_FeeTierInvalid() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3Adapter.UniswapV3Adapter__InvalidFeeTier.selector,
                200
            )
        );
        adapter.insertFeeTier(200);
    }

    function test_insertFeeTier_RevertIf_FeeTierAlreadyExists() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3Adapter.UniswapV3Adapter__FeeTierExists.selector,
                10000
            )
        );
        adapter.insertFeeTier(10000);
    }

    function test_describePricingPath_DescribePricingPath() public {
        (
            IOracleAdapter.AdapterType adapterType,
            address[][] memory path,
            uint8[] memory decimals
        ) = adapter.describePricingPath(address(1));

        assertEq(
            uint256(adapterType),
            uint256(IOracleAdapter.AdapterType.UNISWAP_V3)
        );
        assertEq(path.length, 0);
        assertEq(decimals.length, 0);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(WETH);

        assertEq(
            uint256(adapterType),
            uint256(IOracleAdapter.AdapterType.UNISWAP_V3)
        );
        assertEq(path[0].length, 1);
        assertEq(path[0][0], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(decimals.length, 1);
        assertEq(decimals[0], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(DAI);

        assertEq(
            uint256(adapterType),
            uint256(IOracleAdapter.AdapterType.UNISWAP_V3)
        );
        assertEq(path[0].length, 4);
        assertEq(path[0][0], 0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19);
        assertEq(path[0][1], 0x60594a405d53811d3BC4766596EFD80fd545A270);
        assertEq(path[0][2], 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
        assertEq(path[0][3], 0xa80964C5bBd1A0E95777094420555fead1A26c1e);
        assertEq(decimals.length, 2);
        assertEq(decimals[0], 18);
        assertEq(decimals[1], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(USDC);

        assertEq(
            uint256(adapterType),
            uint256(IOracleAdapter.AdapterType.UNISWAP_V3)
        );
        assertEq(path[0].length, 4);
        assertEq(path[0][0], 0xE0554a476A092703abdB3Ef35c80e0D76d32939F);
        assertEq(path[0][1], 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        assertEq(path[0][2], 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        assertEq(path[0][3], 0x7BeA39867e4169DBe237d55C8242a8f2fcDcc387);
        assertEq(decimals.length, 2);
        assertEq(decimals[0], 6);
        assertEq(decimals[1], 18);
    }
}
