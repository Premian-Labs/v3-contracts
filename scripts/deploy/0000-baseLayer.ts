import {
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import { goerliFeeds } from '../../utils/addresses';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let feeReceiver: string;
  let chainlinkAdapter: string;

  if (chainId === 42161) {
    // Arbitrum addresses
    weth = arbitrumAddresses.tokens.WETH;
    wbtc = arbitrumAddresses.tokens.WBTC;
    feeReceiver = '';
  } else if (chainId === 5) {
    // Goerli addresses
    weth = goerliAddresses.tokens.WETH;
    wbtc = goerliAddresses.tokens.WBTC;
    feeReceiver = '0x589155f2F38B877D7Ac3C1AcAa2E42Ec8a9bb709';
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

  const chainlinkAdapterProxy = await new ChainlinkAdapterProxy__factory(
    deployer,
  ).deploy(chainlinkAdapterImpl.address);
  await chainlinkAdapterProxy.deployed();

  console.log(`ChainlinkAdapter proxy : ${chainlinkAdapterProxy.address}`);

  chainlinkAdapter = chainlinkAdapterProxy.address;

  if (chainId === 5) {
    // Goerli
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(goerliFeeds);
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
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
