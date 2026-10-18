import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'test/playwright',
  timeout: 10_000, // Simple smoke test shouldn't take long
  fullyParallel: true,
  reporter: [['list'], ['html', { outputFolder: 'assets/playwright-report' }]],
  use: {
    headless: true,
    baseURL: process.env.TEST_URL || 'http://localhost:4000',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } }
  ],
  outputDir: 'assets/test-results'
});
