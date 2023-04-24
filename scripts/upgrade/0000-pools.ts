import { Premia__factory } from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import { ContractAddresses } from '../../utils/deployment/types';
import { FacetCut, FacetCutAction, getSelectors } from '../utils/diamond';
import fs from 'fs';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let addresses: ContractAddresses;
  let addressesPath: string;
  let premiaDiamond: string;
  let poolFactory: string;
  let router: string;
  let exchangeHelper: string;
  let vxPremia: string;
  let weth: string;
  let chainlinkAdapter: string;
  let feeReceiver: string;
  let updateFacets: boolean;

  if (chainId === 42161) {
    // Arbitrum
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    feeReceiver = '';
    updateFacets = false;
  } else if (chainId === 5) {
    // Goerli
    addresses = goerliAddresses;
    addressesPath = 'utils/deployment/goerli.json';
    feeReceiver = '0x589155f2F38B877D7Ac3C1AcAa2E42Ec8a9bb709';
    updateFacets = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  premiaDiamond = addresses.PremiaDiamond;
  poolFactory = addresses.PoolFactoryProxy;
  router = addresses.ERC20Router;
  exchangeHelper = addresses.ExchangeHelper;
  vxPremia = addresses.VxPremia;
  weth = addresses.tokens.WETH;
  chainlinkAdapter = addresses.ChainlinkAdapterProxy;

  //////////////////////////

  const log = true;
  const isDevMode = false;

  const deployedFacets = await PoolUtil.deployPoolImplementations(
    deployer,
    poolFactory,
    router,
    exchangeHelper,
    vxPremia,
    weth,
    feeReceiver,
    log,
    isDevMode,
  );

  // Save new addresses
  for (const el of deployedFacets) {
    (addresses as any)[el.name] = el.address;
  }
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));

  //

  if (updateFacets) {
    const diamond = Premia__factory.connect(premiaDiamond, deployer);

    const facets = await diamond.facets();

    let selectorsToRemove: string[] = [];
    for (const el of facets.filter((el) => el.target != diamond.address)) {
      selectorsToRemove = selectorsToRemove.concat(el.selectors);
    }

    const facetCuts: FacetCut[] = [
      {
        target: ethers.constants.AddressZero,
        selectors: selectorsToRemove,
        action: FacetCutAction.REMOVE,
      },
    ];

    let registeredSelectors = [
      diamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    for (const el of deployedFacets) {
      const selectors = getSelectors(el.interface, registeredSelectors);

      facetCuts.push({
        action: FacetCutAction.ADD,
        target: el.address,
        selectors,
      });

      registeredSelectors = registeredSelectors.concat(selectors);
    }

    await diamond.diamondCut(facetCuts, ethers.constants.AddressZero, '0x');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
