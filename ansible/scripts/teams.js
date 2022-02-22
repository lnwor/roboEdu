const puppeteer = require('puppeteer');

(async () => {
    const browser = await puppeteer.launch({ args: ['--disable-notifications', '--use-fake-ui-for-media-stream', '--window-size=1920,1080', '--kiosk'], headless: false, defaultViewport: { width: 1920, height: 1080 }, executablePath: '/usr/bin/google-chrome', ignoreDefaultArgs: ["--enable-automation"] });
    const page = await browser.newPage();

    page.on('dialog', async dialog => {
        await dialog.dismiss();
        await browser.close();
    });

    await page.goto('https://teams.microsoft.com/_#');

    await page.waitForSelector('input[id="i0116"]');
    await page.waitForTimeout(100);
    await page.focus('input[id="i0116"]');
    await page.keyboard.type('{{ username }}', { delay: 100 })
    await page.click('input[value="Next"]');

    await page.waitForSelector('span[id="submitButton"]');
    await page.waitForTimeout(100);
    await page.keyboard.type('{{ password }}', { delay: 100 })
    await page.click('span[id="submitButton"]');

    await page.waitForSelector('input[id="idSIButton9"]');
    await page.waitForTimeout(100);
    await page.click('input[id="idSIButton9"]');

    await page.waitForSelector('div.teams-title');
    await page.waitForTimeout(100);
    await page.goto('{{ link }}');

    await page.waitForTimeout(10000);

    await page.waitForSelector('button[ng-click="ctrl.joinMeeting()"]');
    await page.waitForTimeout(100);
    await page.click('button[ng-click="ctrl.joinMeeting()"]');

    await page.waitForTimeout(10000);

    await page.waitForSelector('button[id="chat-button"]');
    await page.waitForTimeout(100);
    await page.click('button[id="chat-button"]');

    await page.waitForSelector('button[id="callingButtons-showMoreBtn"]');
    await page.waitForTimeout(100);
    await page.click('button[id="callingButtons-showMoreBtn"]');

    await page.waitForSelector('button[id="full-screen-button"]');
    await page.waitForTimeout(100);
    await page.click('button[id="full-screen-button"]');

    await page.waitForSelector('button[ng-click="ctrl.closePopup($event)"]', { timeout: 0 });
    await page.waitForTimeout(100);
    await page.click('button[ng-click="ctrl.closePopup($event)"]', { timeout: 0 });

    debugger;

})();
