import { Premia__factory } from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import goerliAddresses from '../../utils/deployment/goerli.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';
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
  let referral: string;
  let vaultRegistry: string;
  let userSettings: string;
  let vxPremia: string;
  let weth: string;
  let feeReceiver: string;
  let updateFacets: boolean;

  if (chainId === ChainID.Arbitrum) {
    addresses = arbitrumAddresses;
    addressesPath = 'utils/deployment/arbitrum.json';
    feeReceiver = '';
    updateFacets = false;
  } else if (chainId === ChainID.Goerli) {
    addresses = goerliAddresses;
    addressesPath = 'utils/deployment/goerli.json';
    feeReceiver = '0x589155f2F38B877D7Ac3C1AcAa2E42Ec8a9bb709';
    updateFacets = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    feeReceiver = '0x589155f2F38B877D7Ac3C1AcAa2E42Ec8a9bb709';
    updateFacets = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  premiaDiamond = addresses.PremiaDiamond;
  poolFactory = addresses.PoolFactoryProxy;
  router = addresses.ERC20Router;
  referral = addresses.ReferralProxy;
  userSettings = addresses.UserSettingsProxy;
  vxPremia = addresses.VxPremiaProxy;
  weth = addresses.tokens.WETH;
  vaultRegistry = addresses.VaultRegistryProxy;

  //////////////////////////

  const log = true;
  const isDevMode = false;

  const deployedFacets = await PoolUtil.deployPoolImplementations(
    deployer,
    poolFactory,
    router,
    userSettings,
    vxPremia,
    weth,
    feeReceiver,
    referral,
    vaultRegistry,
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
