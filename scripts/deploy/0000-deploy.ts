import { ethers } from 'hardhat';
import { PoolUtil } from '../../utils/PoolUtil';
import { parseEther } from 'ethers/lib/utils';
import {
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy__factory,
} from '../../typechain';

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
    weth = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1';
    wbtc = '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f';
    chainlinkAdapter = '';
    feeReceiver = '';
  } else if (chainId === 5) {
    // Goerli addresses
    weth = '';
    wbtc = '';
    chainlinkAdapter = '';
    feeReceiver = '';
  } else {
    throw new Error('ChainId not implemented');
  }
  //////////////////////////
  // Deploy ChainlinkAdapter

  if (chainlinkAdapter === '') {
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
