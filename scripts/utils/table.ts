import fs from 'fs';
import _ from 'lodash';
import * as prettier from 'prettier';
import { render } from 'mustache';
import path from 'path';

import {
  getContractFilePath,
  getContractFilePaths,
  inferContractDescription,
  inferContractName,
} from './file';
import {
  BlockExplorerUrl,
  ChainID,
  ChainName,
  DeploymentPath,
} from './types.chain';
import {
  ContractKey,
  ContractType,
  DeploymentMetadata,
} from './types.deployment';

function displayHeader() {
  if (this.name.length > 0 || this.name !== '') return `|**${this.name}**|||||`;
  else return '||||||';
}

function displayAddress() {
  if (this.address.length > 0 || this.address !== '')
    return `\`${this.address}\``;
  else return '';
}

function displayEtherscanUrl() {
  if (this.address.length > 0 || this.address !== '')
    return `[🔗](${this.etherscanUrl}/address/${this.address})`;
  else return '';
}

function displayFilePathUrl() {
  if (
    (this.commitHash.length > 0 || this.commitHash !== '') &&
    (this.filePath.length > 0 || this.filePath !== '')
  ) {
    return `[📁](https://github.com/Premian-Labs/v3-contracts/blob/${this.commitHash}/${this.filePath})`;
  } else return '';
}

export async function generateTables(chainId: ChainID, log = false) {
  const chain = ChainName[chainId];
  const etherscanUrl = BlockExplorerUrl[chainId];
  const deploymentPath = DeploymentPath[chainId];

  const deploymentMetadata = JSON.parse(
    fs.readFileSync(`${deploymentPath}/metadata.json`).toString(),
  ) as DeploymentMetadata;

  let tableView: TableData = {
    categories: {
      vaults: {
        name: 'Vault',
        chain: '',
        sections: [],
        displayHeader,
      },
      optionPS: {
        name: 'Physically Settled Option',
        chain: '',
        sections: [],
        displayHeader,
      },
      optionReward: {
        name: 'Option Reward',
        chain: '',
        sections: [],
        displayHeader,
      },
      core: {
        name: 'Core Contract',
        chain: '',
        sections: [],
        displayHeader,
      },
    },
  };

  tableView = updateTableView(
    tableView,
    deploymentMetadata,
    chain,
    etherscanUrl,
  );
  writeTables(tableView, deploymentPath, chain, log);
}

function updateTableView(
  tableView: TableData,
  deploymentMetadata: DeploymentMetadata,
  chain: string,
  etherscanUrl: string,
) {
  const contractFilePaths = getContractFilePaths();

  for (const key in deploymentMetadata) {
    // Update Vaults, OptionReward, and OptionPS views
    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      if (chain === 'Arbitrum Nova') continue;
      const category = tableView.categories[key];
      category.chain = chain;

      category.sections.push({
        name: '',
        contracts: [],
      });

      for (let contract in deploymentMetadata[key]) {
        const contractData = deploymentMetadata[key][contract];

        const contractInfo: Contract = {
          name: contract,
          description: '',
          address: contractData.address,
          etherscanUrl,
          displayAddress,
          displayEtherscanUrl,
        };

        category.sections[0].contracts.push(contractInfo);
      }
    } else if (key === 'core') {
      for (const contract in deploymentMetadata.core) {
        // Update Core view
        const category = tableView.categories.core;
        category.chain = chain;

        const contractData = deploymentMetadata.core[contract as ContractKey];
        const contractName = inferContractName(
          contract,
          contractData.contractType,
        );

        const filePath = getContractFilePath(contractName, contractFilePaths);

        let sectionIndex = -1;
        let section = '--UNRESOLVED--';
        if (filePath) {
          section = filePath.split('/')[1];
          // Capitalize first letter of section
          section = section.charAt(0).toUpperCase() + section.slice(1);

          sectionIndex = _.findIndex(category.sections, ['name', section]);
        } else {
          console.warn(`[WARNING] No file found for ${contractName}`);
        }

        if (sectionIndex === -1) {
          category.sections.push({
            name: section,
            contracts: [],
          });

          sectionIndex = category.sections.length - 1;
        }

        const contractInfo: Contract = {
          name: contractName,
          description: inferContractDescription(
            contract,
            contractData.contractType,
          ),
          address: contractData.address,
          commitHash: contractData.commitHash,
          etherscanUrl,
          filePath,
          displayAddress,
          displayEtherscanUrl,
          displayFilePathUrl,
        };

        category.sections[sectionIndex].contracts.push(contractInfo);
      }
    }
  }

  // sort sections by name (Core contracts only)
  tableView.categories.core.sections = _.sortBy(
    tableView.categories.core.sections,
    ['name'],
  );

  // sort contracts by name (Core contracts only)
  tableView.categories.core.sections.forEach((section, i) => {
    tableView.categories.core.sections[i].contracts = _.sortBy(
      section.contracts,
      ['name'],
    );
  });

  return tableView;
}

function writeTables(
  tableView: TableData,
  deploymentPath: string,
  chain: string,
  log = false,
) {
  for (const key in tableView.categories) {
    const category = tableView.categories[key];

    let template = tableTemplate;
    let partial = detailedSummaryPartial;
    let pathKey = 'core';

    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      if (chain === 'Arbitrum Nova') continue;
      template = tableTemplateNoHeader;
      partial = summaryPartial;
      pathKey = key;
    }

    // Generate md file from template
    let table = render(template, category, { partial });

    // Prettify table markdown
    table = prettier.format(table, { parser: 'markdown' });

    // Overwrite {pathKey}Table.md
    const tablePath = path.join(deploymentPath, pathKey + 'Table.md');
    fs.writeFileSync(tablePath, table);

    if (log) {
      console.log(`Table generated at ${tablePath}`);
    }
  }
}

//////////////////////
// Templates
//////////////////////

const tableTemplateNoHeader = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |
|--------------|-----------|-------|----|
{{#sections}}
{{>partial}}
{{/sections}}`;

const summaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|\n{{/contracts}}`;

const tableTemplate = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |    |
|--------------|-----------|-------|----|----|
{{#sections}}
{{displayHeader}}
{{>partial}}
{{/sections}}`;

const detailedSummaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|{{{displayFilePathUrl}}}|\n{{/contracts}}`;

//////////////////////
// Types
//////////////////////

interface TableData {
  categories: {
    [key: string]: {
      name: string;
      chain: string;
      sections: Section[];
      displayHeader: () => string;
    };
  };
}

type Section = {
  name: string;
  contracts: Contract[];
};

type Contract = {
  name: string;
  description: string;
  type?: ContractType;
  address: string;
  commitHash?: string;
  etherscanUrl: string;
  filePath?: string;
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};
