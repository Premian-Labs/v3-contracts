// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import "../Addresses.sol";
import {Assertions} from "../Assertions.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";
import {ChainlinkAdapter} from "contracts/adapter/chainlink/ChainlinkAdapter.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ChainlinkOraclePriceStub} from "contracts/test/adapter/ChainlinkOraclePriceStub.sol";

contract ChainlinkAdapterTest is Test, Assertions {
    struct Path {
        IChainlinkAdapter.PricingPath path;
        address tokenIn;
        address tokenOut;
    }

    uint256 mainnetFork;

    Path[] paths;
    ChainlinkAdapter adapter;
    uint256 target;

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL, 16597500);
        vm.selectFork(mainnetFork);

        target = 1676016000;

        // prettier-ignore
        {
            // ETH_USD
            paths.push(Path(IChainlinkAdapter.PricingPath.ETH_USD, WETH, CHAINLINK_USD));  // IN is ETH, OUT is USD
            paths.push(Path(IChainlinkAdapter.PricingPath.ETH_USD, CHAINLINK_USD, WETH)); // IN is USD, OUT is ETH
            paths.push(Path(IChainlinkAdapter.PricingPath.ETH_USD, CHAINLINK_ETH, CHAINLINK_USD)); // IN is ETH, OUT is USD

            // TOKEN_USD
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, DAI, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, AAVE, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD
            // Note: Assumes WBTC/USD feed exists
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, CHAINLINK_USD, WBTC)); // IN (tokenB) is USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD, WBTC, CHAINLINK_USD)); // IN (tokenA) => OUT (tokenB) is USD

            // TOKEN_ETH
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, BNT, WETH)); // IN (tokenA) => OUT (tokenB) is ETH
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, AXS, WETH)); // IN (tokenB) => OUT (tokenA) is ETH
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH, WETH, CRV)); // IN (tokenA) is ETH => OUT (tokenB)

            // TOKEN_USD_TOKEN
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, CRV, AAVE)); // IN (tokenB) => USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, DAI, AAVE)); // IN (tokenA) => USD => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, AAVE, DAI)); // IN (tokenB) => USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, CRV, USDC)); // IN (tokenB) => USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, USDC, COMP)); // IN (tokenA) => USD => OUT (tokenB)
            // Note: Assumes WBTC/USD feed exists
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, DAI, WBTC)); // IN (tokenB) => USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN, WBTC, USDC)); // IN (tokenA) => USD => OUT (tokenB)

            // TOKEN_ETH_TOKEN
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH_TOKEN, BOND, AXS)); // IN (tokenA) => ETH => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_ETH_TOKEN, ALPHA, BOND)); // IN (tokenB) => ETH => OUT (tokenA)

            // A_USD_ETH_B
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, FXS, WETH)); // IN (tokenA) => USD, OUT (tokenB) is ETH
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, WETH, MATIC)); // IN (tokenB) is ETH, USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, USDC, AXS)); // IN (tokenA) is USD, ETH => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, ALPHA, DAI)); // IN (tokenB) => ETH, OUT is USD (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, DAI, ALPHA));
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, FXS, AXS)); // IN (tokenA) => USD, ETH => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, ALPHA, MATIC)); // IN (tokenB) => ETH, USD => OUT (tokenA)
            // Note: Assumes WBTC/USD feed exists
            paths.push(Path(IChainlinkAdapter.PricingPath.A_USD_ETH_B, WETH, WBTC)); // IN (tokenB) => ETH, USD => OUT (tokenA)

            // A_ETH_USD_B
            // We can't test the following two cases, because we would need a token that is
            // supported by chainlink and lower than USD (address(840))
            // - IN (tokenA) => ETH, OUT (tokenB) is USD
            // - IN (tokenB) is USD, ETH => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, WETH, IMX)); // IN (tokenA) is ETH, USD => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, IMX, WETH)); // IN (tokenB) => USD, OUT is ETH (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, AXS, IMX)); // IN (tokenA) => ETH, USD => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, FXS, BOND)); // IN (tokenB) => ETH, USD => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.A_ETH_USD_B, BOND, FXS)); // IN (tokenA) => USD, ETH => OUT (tokenB)

            // TOKEN_USD_BTC_WBTC
            // Note: Assumes WBTC/USD feed does not exist
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, CHAINLINK_USD)); // IN (tokenA) => BTC, OUT is USD
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, CHAINLINK_BTC)); // IN (tokenA) => BTC, OUT is BTC
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, WETH)); // IN (tokenA) => BTC, OUT is ETH (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WETH, WBTC)); // IN (tokenB) is ETH, BTC => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, DAI, WBTC)); // IN (tokenB) => USD, BTC => OUT (tokenA)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, USDC)); // IN (tokenA) => BTC, USD => OUT (tokenB)
            paths.push(Path(IChainlinkAdapter.PricingPath.TOKEN_USD_BTC_WBTC, WBTC, BNT)); // IN (tokenA) => USD,  BTC => OUT (tokenB)
        }

        address implementation = address(new ChainlinkAdapter(WETH, WBTC));
        address proxy = address(new ProxyUpgradeableOwnable(implementation));
        adapter = ChainlinkAdapter(proxy);

        adapter.batchRegisterFeedMappings(feeds());
    }

    function _deployStub() internal returns (ChainlinkOraclePriceStub stub, address stubCoin) {
        stub = new ChainlinkOraclePriceStub();
        stubCoin = address(100);

        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(stubCoin, CHAINLINK_USD, address(stub));

        adapter.batchRegisterFeedMappings(data);
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        return (stub, stubCoin);
    }

    function _addWBTCUSD(IChainlinkAdapter.PricingPath path) internal {
        if (
            path != IChainlinkAdapter.PricingPath.TOKEN_USD &&
            path != IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN &&
            path != IChainlinkAdapter.PricingPath.A_USD_ETH_B
        ) return;

        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(WBTC, CHAINLINK_USD, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

        adapter.batchRegisterFeedMappings(data);
    }

    function test_isPairSupported_ReturnTrue_IfPairCachedAndPathExists() public {
        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < paths.length; i++) {
            Path memory p = paths[i];

            _addWBTCUSD(p.path);

            adapter.upsertPair(p.tokenIn, p.tokenOut);

            (bool isCached, bool hasPath) = adapter.isPairSupported(p.tokenIn, p.tokenOut);
            assertTrue(isCached);
            assertTrue(hasPath);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_isPairSupported_ReturnFalse_IfPairNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPathDoesNotExist() public {
        (, bool hasPath) = adapter.isPairSupported(WETH, WBTC);
        assertTrue(hasPath);
    }

    function test_upserPair_ShouldNotRevert_IfCalledMultipleTime_ForSamePair() public {
        adapter.upsertPair(WETH, DAI);
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertTrue(isCached);

        adapter.upsertPair(WETH, DAI);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, address(0), WETH)
        );
        adapter.upsertPair(address(0), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, WBTC, address(0))
        );
        adapter.upsertPair(WBTC, address(0));
    }

    function test_batchRegisterFeedMappings_RevertIf_TokenEqualDenomination() public {
        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(EUL, EUL, address(1));

        vm.expectRevert(abi.encodeWithSelector(IFeedRegistry.FeedRegistry__TokensAreSame.selector, EUL, EUL));
        adapter.batchRegisterFeedMappings(data);
    }

    function test_batchRegisterFeedMappings_RevertIf_TokenOrDenominationIsZero() public {
        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(address(0), DAI, address(1));
        vm.expectRevert(IFeedRegistry.FeedRegistry__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);

        data[0] = IFeedRegistry.FeedMappingArgs(EUL, address(0), address(1));
        vm.expectRevert(IFeedRegistry.FeedRegistry__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);
    }

    function test_feed_ReturnFeed() public {
        IFeedRegistry.FeedMappingArgs[] memory _feeds = feeds();

        for (uint256 i = 0; i < _feeds.length; i++) {
            assertEq(adapter.feed(_feeds[i].token, _feeds[i].denomination), _feeds[i].feed);
        }
    }

    function test_feed_ReturnZeroAddress_IfFeedDoesNotExist() public {
        assertEq(adapter.feed(EUL, DAI), address(0));
    }

    function test_quote_ReturnQuoteForPair() public {
        // Expected values exported from Defilama
        UD60x18[39] memory expected = [
            ud(1551253958184865268777), // WETH CHAINLINK_USD
            ud(644639773341889), // CHAINLINK_USD WETH
            ud(1552089999999999918145), // CHAINLINK_ETH CHAINLINK_USD
            ud(999758000000000036), // DAI CHAINLINK_USD
            ud(79200000000000002842), // AAVE CHAINLINK_USD
            ud(45722646426775), // CHAINLINK_USD WBTC
            ud(21871000000000000000000), // WBTC CHAINLINK_USD
            ud(282273493583309), // BNT WETH
            ud(6617057201666803), // AXS WETH
            ud(1570958490531603047202), // WETH CRV
            ud(12467891414141414), // CRV AAVE
            ud(12623207070707071), // DAI AAVE
            ud(79219171039391525824), // AAVE DAI
            ud(987652555205930871), // CRV USDC
            ud(20230716309186565), // USDC COMP
            ud(45711581546340), // DAI WBTC
            ud(21875331315600487869233), // WBTC USDC
            ud(410573778449028981), // BOND AXS
            ud(28582048972903472), // ALPHA BOND
            ud(7725626669884812), // FXS WETH
            ud(1202522448205321779824), // WETH MATIC
            ud(97446588693957115), // USDC AXS
            ud(120430653003309712), // ALPHA DAI
            ud(8303533818524737597), // DAI ALPHA
            ud(1168071047867190515), // FXS AXS
            ud(93334502934327837), // ALPHA MATIC
            ud(70927436248222092), // WETH WBTC
            ud(1701565115821158997278), // WETH IMX
            ud(587694229684187), // IMX WETH
            ud(11254158609047422601), // AXS IMX
            ud(2844972351326624072), // FXS BOND
            ud(351497264827088818), // BOND FXS
            ud(21871000000000000000000), // WBTC CHAINLINK_USD
            ud(999177669148887615), // WBTC CHAINLINK_BTC
            ud(14098916482760458280), // WBTC WETH
            ud(70927436248222092), // WETH WBTC
            ud(45711581546340), // DAI WBTC
            ud(21875331315600487869233), // WBTC USDC
            ud(49947716676413132518064) // WBTC BNT
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < paths.length; i++) {
            Path memory p = paths[i];
            _addWBTCUSD(p.path);
            adapter.upsertPair(p.tokenIn, p.tokenOut);

            UD60x18 quote = adapter.quote(p.tokenIn, p.tokenOut);

            assertApproxEqAbs(
                quote.unwrap(),
                expected[i].unwrap(),
                (expected[i].unwrap() * 3) / 100 // 3% tolerance
            );

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_quote_ReturnQuoteUsingCorrectDenomination() public {
        address tokenIn = WETH;
        address tokenOut = DAI;

        adapter.upsertPair(tokenIn, tokenOut);

        UD60x18 quote = adapter.quote(tokenIn, tokenOut);
        UD60x18 invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertEq(quote, ud(1e18) / invertedQuote);

        //

        tokenIn = CRV;
        tokenOut = AAVE;

        adapter.upsertPair(tokenIn, tokenOut);

        quote = adapter.quote(tokenIn, tokenOut);
        invertedQuote = adapter.quote(tokenOut, tokenIn);

        assertEq(quote, ud(1e18) / invertedQuote);
    }

    function test_quote_ReturnCorrectQuote_IfPathExistsButNotCached() public {
        UD60x18 quoteBeforeUpsert = adapter.quote(WETH, DAI);

        adapter.upsertPair(WETH, DAI);
        UD60x18 quote = adapter.quote(WETH, DAI);

        assertEq(quote, quoteBeforeUpsert);
    }

    function test_quote_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairNotSupported.selector, WETH, address(0))
        );
        adapter.quote(WETH, address(0));
    }

    function test_quote_CatchRevert() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = target - 90000;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.LAST_ROUND_DATA_REVERT_WITH_REASON, prices, timestamps);

        vm.expectRevert("reverted with reason");
        adapter.quote(stubCoin, CHAINLINK_USD);

        //

        stub.setup(ChainlinkOraclePriceStub.FailureMode.LAST_ROUND_DATA_REVERT, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__LatestRoundDataCallReverted.selector, "")
        );
        adapter.quote(stubCoin, CHAINLINK_USD);
    }

    function test_quoteFrom_ReturnQuoteForPairFromTarget() public {
        // Expected values exported from Defilama
        UD60x18[39] memory expected = [
            ud(1552329999999999927240), // WETH CHAINLINK_USD
            ud(644192922896549), // CHAINLINK_USD WETH
            ud(1553210000000000036380), // CHAINLINK_ETH CHAINLINK_USD
            ud(1000999999999999890), // DAI CHAINLINK_USD
            ud(79620000000000004547), // AAVE CHAINLINK_USD
            ud(45583006655119), // CHAINLINK_USD WBTC
            ud(21938000000000000000000), // WBTC CHAINLINK_USD
            ud(282841277305728), // BNT WETH
            ud(6609419388918594), // AXS WETH
            ud(1560637272199920062121), // WETH CRV
            ud(12492803315749812), // CRV AAVE
            ud(12572218035669427), // DAI AAVE
            ud(79540459540459551135), // AAVE DAI
            ud(992691616766467111), // CRV USDC
            ud(20242424242424242), // USDC COMP
            ud(45628589661774), // DAI WBTC
            ud(21894211576846308162203), // WBTC USDC
            ud(413255360623781709), // BOND AXS
            ud(28558726415094340), // ALPHA BOND
            ud(7930014880856519), // FXS WETH
            ud(1232007936507936392445), // WETH MATIC
            ud(97660818713450295), // USDC AXS
            ud(120968031968031978), // ALPHA DAI
            ud(8266646846534365878), // DAI ALPHA
            ud(1199805068226120985), // FXS AXS
            ud(96102380952380953), // ALPHA MATIC
            ud(70759868720940824), // WETH WBTC
            ud(1732435753354485541422), // WETH IMX
            ud(577221982439301), // IMX WETH
            ud(11450394458276926812), // AXS IMX
            ud(2903301886792452713), // FXS BOND
            ud(344435418359057666), // BOND FXS
            ud(21938000000000000000000), // WBTC CHAINLINK_USD
            ud(999225688909132326), // WBTC CHAINLINK_BTC
            ud(14132304342504493633), // WBTC WETH
            ud(70759868720940824), // WETH WBTC
            ud(45628589661774), // DAI WBTC
            ud(21894211576846308162203), // WBTC USDC
            ud(49965494701215997338295) // WBTC BNT
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < paths.length; i++) {
            Path memory p = paths[i];
            _addWBTCUSD(p.path);
            adapter.upsertPair(p.tokenIn, p.tokenOut);

            UD60x18 quote = adapter.quoteFrom(p.tokenIn, p.tokenOut, target);

            assertApproxEqAbs(
                quote.unwrap(),
                expected[i].unwrap(),
                (expected[i].unwrap() * 3) / 100 // 3% tolerance
            );

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_quoteFrom_CatchRevert() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        int256[] memory prices = new int256[](3);
        uint256[] memory timestamps = new uint256[](3);

        prices[0] = 100000000000;
        prices[1] = 100000000000;
        prices[2] = 100000000000;

        timestamps[0] = target + 3;
        timestamps[1] = target + 2;
        timestamps[2] = target + 1;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.GET_ROUND_DATA_REVERT_WITH_REASON, prices, timestamps);

        vm.expectRevert("reverted with reason");
        adapter.quoteFrom(stubCoin, CHAINLINK_USD, target);

        //

        stub.setup(ChainlinkOraclePriceStub.FailureMode.GET_ROUND_DATA_REVERT, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__GetRoundDataCallReverted.selector, "")
        );
        adapter.quoteFrom(stubCoin, CHAINLINK_USD, target);
    }

    function test_quoteFrom_RevertIf_TargetIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidTarget.selector, 0, block.timestamp)
        );
        adapter.quoteFrom(WETH, DAI, 0);
    }

    function test_quoteFrom_RevertIf_TargetGtBlockTimestamp() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__InvalidTarget.selector,
                block.timestamp + 1,
                block.timestamp
            )
        );
        adapter.quoteFrom(WETH, DAI, block.timestamp + 1);
    }

    function test_quoteFrom_WhenStalePrice_ReturnStalePrice_IfCall12HoursAfterTarget() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = target - 90000;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        vm.warp(target + 43200);
        int256 stalePrice = stub.price(0);

        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(stalePrice) * 1e10));
    }

    function test_quoteFrom_WhenStalePrice_RevertIf_CallWithin12HoursOfTarget() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = target - 90000;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter.ChainlinkAdapter__PriceAfterTargetIsStale.selector,
                target,
                timestamps[0],
                block.timestamp
            )
        );
        adapter.quoteFrom(stubCoin, CHAINLINK_USD, target);
    }

    function _test_quoteFrom_WhenFreshPrice_ReturnClosestPriceToTarget() public {
        (ChainlinkOraclePriceStub stub, address stubCoin) = _deployStub();

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 1000000000000;
        timestamps[0] = target + 100;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        int256 freshPrice = stub.price(0);
        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));

        //

        prices = new int256[](3);
        timestamps = new uint256[](3);

        prices[0] = 100000000000;
        prices[1] = 200000000000;
        prices[2] = 300000000000;

        timestamps[0] = target + 100;
        timestamps[1] = target + 200;
        timestamps[2] = target + 300;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        freshPrice = stub.price(0);
        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));

        //

        prices = new int256[](4);
        timestamps = new uint256[](4);

        prices[0] = 50000000000;
        prices[1] = 100000000000;
        prices[2] = 200000000000;
        prices[3] = 300000000000;

        timestamps[0] = target - 50;
        timestamps[1] = target + 100;
        timestamps[2] = target + 200;
        timestamps[3] = target + 300;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        freshPrice = stub.price(0);
        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));

        //

        prices = new int256[](4);
        timestamps = new uint256[](4);

        prices[0] = 50000000000;
        prices[1] = 100000000000;
        prices[2] = 200000000000;
        prices[3] = 300000000000;

        timestamps[0] = target - 100;
        timestamps[1] = target + 50;
        timestamps[2] = target + 300;
        timestamps[3] = target + 500;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        freshPrice = stub.price(1);
        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));

        //

        prices = new int256[](2);
        timestamps = new uint256[](2);

        prices[0] = 50000000000;
        prices[1] = 100000000000;

        timestamps[0] = target - 100;
        timestamps[1] = target - 50;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.NONE, prices, timestamps);

        freshPrice = stub.price(1);
        assertEq(adapter.quoteFrom(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
    }

    function test_quoteFrom_WhenFreshPrice_ReturnClosestPriceToTarget_IfCallWithin12HoursOfTarget() public {
        _test_quoteFrom_WhenFreshPrice_ReturnClosestPriceToTarget();
    }

    function test_quoteFrom_WhenFreshPrice_ReturnClosestPriceToTarget_IfCall12HoursAfterTarget() public {
        vm.warp(target + 43200);
        _test_quoteFrom_WhenFreshPrice_ReturnClosestPriceToTarget();
    }

    function test_describePricingPath_Success() public {
        (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
            .describePricingPath(address(1));

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.CHAINLINK));
        assertEq(path.length, 0);
        assertEq(decimals.length, 0);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(WETH);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.CHAINLINK));
        assertEq(path.length, 1);
        assertEq(path[0][0], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(decimals.length, 1);
        assertEq(decimals[0], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(DAI);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.CHAINLINK));
        assertEq(path.length, 1);
        assertEq(path[0][0], 0x158228e08C52F3e2211Ccbc8ec275FA93f6033FC);
        assertEq(decimals.length, 1);
        assertEq(decimals[0], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(ENS);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.CHAINLINK));
        assertEq(path.length, 2);
        assertEq(path[0][0], 0x780f1bD91a5a22Ede36d4B2b2c0EcCB9b1726a28);
        assertEq(path[1][0], 0x37bC7498f4FF12C19678ee8fE19d713b87F6a9e6);
        assertEq(decimals.length, 2);
        assertEq(decimals[0], 8);
        assertEq(decimals[0], 8);
    }

    function test_pricingPath_ReturnPathForPair() public {
        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < paths.length; i++) {
            Path memory p = paths[i];

            _addWBTCUSD(p.path);

            adapter.upsertPair(p.tokenIn, p.tokenOut);

            IChainlinkAdapter.PricingPath path1 = adapter.pricingPath(p.tokenIn, p.tokenOut);
            IChainlinkAdapter.PricingPath path2 = adapter.pricingPath(p.tokenOut, p.tokenIn);

            assertEq(uint256(path1), uint256(p.path));
            assertEq(uint256(path2), uint256(p.path));

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }
}
