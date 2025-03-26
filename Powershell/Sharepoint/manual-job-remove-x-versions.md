1. install the following https://www.microsoft.com/en-us/download/details.aspx?id=35588
2. connect-SPOService -Url https://XXXYYY-admin.sharepoint.com/
3.1  New-SPOSiteFileVersionBatchDeleteJob -Identity https://xxxx.sharepoint.com/sites/yyyyyy -MajorVersionLimit 2 -MajorWithMinorVersionsLimit 0
3.2  New-SPOSiteFileVersionBatchDeleteJob -Identity https://contoso.sharepoint.com/sites/site1 -DeleteBeforeDays 3

5. check batch job progress:  Get-SPOSiteFileVersionBatchDeleteJobProgress -identity "https://xxxx.sharepoint.com/sites/yyyyyy"