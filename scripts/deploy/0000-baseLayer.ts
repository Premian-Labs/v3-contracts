import {
  ProxyUpgradeableOwnable__factory,
  ChainlinkAdapter__factory,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
  UniswapV3ChainlinkAdapter__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  goerliFeeds,
  arbitrumGoerliFeeds,
  UNISWAP_V3_FACTORY,
} from '../../utils/addresses';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import { ChainID } from '../../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let vxPremia: string | undefined;
  let feeReceiver: string;
  let chainlinkAdapter: string;

  if (chainId === ChainID.Arbitrum) {
    weth = arbitrumAddresses.tokens.WETH;
    wbtc = arbitrumAddresses.tokens.WBTC;
    feeReceiver = arbitrumAddresses.feeReceiver;
    vxPremia = arbitrumAddresses.VxPremiaProxy;
  } else if (chainId === ChainID.Goerli) {
    weth = goerliAddresses.tokens.WETH;
    wbtc = goerliAddresses.tokens.WBTC;
    feeReceiver = goerliAddresses.feeReceiver;
    vxPremia = goerliAddresses.VxPremiaProxy;
  } else if (chainId == ChainID.ArbitrumGoerli) {
    weth = arbitrumGoerliAddresses.tokens.WETH;
    wbtc = arbitrumGoerliAddresses.tokens.WBTC;
    feeReceiver = arbitrumAddresses.feeReceiver;
    vxPremia = arbitrumGoerliAddresses.VxPremiaProxy;
  } else {
    throw new Error('ChainId not implemented');
  }
  //////////////////////////
  // Deploy ChainlinkAdapter
  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(weth, wbtc);
  await chainlinkAdapterImpl.deployed();
  console.log(`ChainlinkAdapter impl : ${chainlinkAdapterImpl.address}`);

  const chainlinkAdapterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(chainlinkAdapterImpl.address);
  await chainlinkAdapterProxy.deployed();

  console.log(`ChainlinkAdapter proxy : ${chainlinkAdapterProxy.address}`);

  chainlinkAdapter = chainlinkAdapterProxy.address;

  if (chainId === ChainID.Goerli) {
    // Goerli
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(goerliFeeds);
  } else if (chainId == ChainID.ArbitrumGoerli) {
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(arbitrumGoerliFeeds);
  } else {
    throw new Error('ChainId not implemented');
  }

  // Deploy UniswapV3Adapter
  const gasPerCardinality = 22250;
  const gasPerPool = 30000;
  const period = 600;
  const cardinalityPerMinute = 100; // Max 1 update per second on 600s period = 60 per minute, to which we add an extra buffer

  const uniswapV3AdapterImpl = await new UniswapV3Adapter__factory(
    deployer,
  ).deploy(UNISWAP_V3_FACTORY, weth, gasPerCardinality, gasPerPool);
  await uniswapV3AdapterImpl.deployed();
  console.log(
    `UniswapV3ChainlinkAdapter impl : ${uniswapV3AdapterImpl.address}`,
  );

  const uniswapV3AdapterProxy = await new UniswapV3AdapterProxy__factory(
    deployer,
  ).deploy(period, cardinalityPerMinute, uniswapV3AdapterImpl.address);
  await uniswapV3AdapterProxy.deployed();

  console.log(
    `UniswapV3ChainlinkAdapter proxy : ${uniswapV3AdapterProxy.address}`,
  );

  // Deploy UniswapV3ChainlinkAdapter
  const uniswapV3ChainlinkAdapterImpl =
    await new UniswapV3ChainlinkAdapter__factory(deployer).deploy(
      chainlinkAdapterProxy.address,
      uniswapV3AdapterProxy.address,
      weth,
    );
  await uniswapV3ChainlinkAdapterImpl.deployed();
  console.log(
    `UniswapV3ChainlinkAdapter impl : ${uniswapV3ChainlinkAdapterImpl.address}`,
  );

  const uniswapV3ChainlinkAdapterProxy =
    await new ProxyUpgradeableOwnable__factory(deployer).deploy(
      uniswapV3ChainlinkAdapterImpl.address,
    );
  await uniswapV3ChainlinkAdapterProxy.deployed();

  console.log(
    `UniswapV3ChainlinkAdapter proxy : ${uniswapV3ChainlinkAdapterProxy.address}`,
  );

  //////////////////////////

  const discountPerPool = parseEther('0.1'); // 10%
  const log = true;
  const isDevMode = false;

  await PoolUtil.deploy(
    deployer,
    weth,
    chainlinkAdapter,
    feeReceiver,
    discountPerPool,
    log,
    isDevMode,
    vxPremia,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
