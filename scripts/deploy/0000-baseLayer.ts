import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import { arbitrumGoerliFeeds, goerliFeeds } from '../../utils/addresses';
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
