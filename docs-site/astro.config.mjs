import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const repoUrl = 'https://github.com/artyomb/nats-async';

export default defineConfig({
  site: 'https://artyomb.github.io',
  base: '/nats-async',
  integrations: [
    starlight({
      title: 'Nats Async',
      description: 'Async Ruby client API for NATS core messaging and JetStream.',
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: repoUrl }],
      editLink: { baseUrl: `${repoUrl}/edit/main/docs-site/` },
      sidebar: [
        {
          label: 'Start Here',
          items: [
            { label: 'Overview', slug: 'index' },
            { label: 'Getting Started', slug: 'getting-started' },
            { label: 'Examples', slug: 'guides/examples' }
          ]
        },
        {
          label: 'Guides',
          items: [
            { label: 'Client Lifecycle', slug: 'guides/client-lifecycle' },
            { label: 'Core Messaging', slug: 'guides/core-messaging' },
            { label: 'Headers And Binary', slug: 'guides/headers-and-binary' },
            { label: 'JetStream', slug: 'guides/jetstream' },
            {
              label: 'Performance',
              items: [
                { label: 'Overview', slug: 'guides/performance' },
                { label: 'Flush Batching', slug: 'guides/flush-batching' }
              ]
            }
          ]
        },
        {
          label: 'Reference',
          items: [
            { label: 'Client API', slug: 'reference/client-api' },
            { label: 'JetStream API', slug: 'reference/jetstream-api' }
          ]
        }
      ]
    })
  ]
});
