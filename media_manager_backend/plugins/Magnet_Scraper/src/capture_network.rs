//! Network request capture tool for reverse engineering Kiteyuan API

use headless_chrome::{Browser, LaunchOptions};
use std::time::Duration;
use anyhow::Result;

fn main() -> Result<()> {
    println!("=== Kiteyuan Network Request Capture ===\n");
    
    let query = "dorcelclub.25.10.03";
    let url = format!("https://demosearch.kiteyuan.info/search?q={}&engine=local_db", query);
    
    println!("Target URL: {}", url);
    println!("Query: {}\n", query);
    
    // Launch browser with network logging
    let launch_options = LaunchOptions::default_builder()
        .headless(false)
        .window_size(Some((1920, 1080)))
        .build()?;
    
    let browser = Browser::new(launch_options)?;
    let tab = browser.new_tab()?;
    
    println!("Browser launched. Opening DevTools...\n");
    
    // Enable network tracking
    let enable_network = r#"
        (function() {
            window.__networkRequests = [];
            
            // Intercept fetch
            const originalFetch = window.fetch;
            window.fetch = function(...args) {
                const url = args[0];
                console.log('[FETCH]', url);
                window.__networkRequests.push({
                    type: 'fetch',
                    url: url,
                    timestamp: new Date().toISOString()
                });
                return originalFetch.apply(this, args);
            };
            
            // Intercept XMLHttpRequest
            const originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                console.log('[XHR]', method, url);
                window.__networkRequests.push({
                    type: 'xhr',
                    method: method,
                    url: url,
                    timestamp: new Date().toISOString()
                });
                return originalOpen.apply(this, arguments);
            };
            
            return true;
        })();
    "#;
    
    // Navigate and inject network interceptor
    println!("Navigating to: {}\n", url);
    tab.navigate_to(&url)?;
    
    // Wait a bit for initial load
    std::thread::sleep(Duration::from_secs(2));
    
    // Inject network interceptor
    tab.evaluate(enable_network, true)?;
    
    println!("Network interceptor installed!");
    println!("Waiting for page to load and make API requests...\n");
    
    // Wait for page to fully load
    std::thread::sleep(Duration::from_secs(5));
    
    // Get captured requests
    let get_requests = r#"
        (function() {
            return window.__networkRequests || [];
        })();
    "#;
    
    let result = tab.evaluate(get_requests, true)?;
    
    println!("=== Captured Network Requests ===\n");
    println!("{:#?}", result);
    
    // Try to get requests from console
    let console_script = r#"
        (function() {
            // Get all network requests from Performance API
            const resources = performance.getEntriesByType('resource');
            return resources.map(r => ({
                name: r.name,
                type: r.initiatorType,
                duration: r.duration
            }));
        })();
    "#;
    
    let resources = tab.evaluate(console_script, true)?;
    println!("\n=== Resources from Performance API ===\n");
    println!("{:#?}", resources);
    
    println!("\n=== Instructions ===");
    println!("1. Browser window is open - press F12 to open DevTools");
    println!("2. Go to Network tab");
    println!("3. Look for XHR/Fetch requests");
    println!("4. Click on '打开' or '复制' button in the search results");
    println!("5. Observe any new API requests");
    println!("\nPress Enter to close browser...");
    
    let mut input = String::new();
    std::io::stdin().read_line(&mut input)?;
    
    Ok(())
}
