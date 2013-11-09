https = require "https"
request = require "request"
fs = require "fs"
Q = require "q"
_ = require "lodash"
xmlBuilder = require "xmlbuilder"

hostname = "stg-apiv2.vevo.com"
apiToken = null

###
 * Gets api token, everytime new
###
getApiToken = ->
   dfrd = Q.defer()

   post_data = JSON.stringify
      "client_id"      : "e962a4ae0b634065b774729ee601a82b"
      "client_secret"  : "9794fb3bcd4b47488380c2bc9e5ef618"
      "grant_type"     : "client_credentials"
      "country"        : "US"
      "locale"         : "en-us"

   options =
      url            : "https://#{hostname}/oauth/token"
      body           : post_data
      method         : "POST"
      headers        : 'Content-Type': 'application/json'

   request options, (err, response, body)->
      if err then dfrd.reject()
      else
         apiToken = JSON.parse(body).access_token
         dfrd.resolve()

   dfrd.promise

###
 * Gets videos data from api
###
getJsonPage = (page) ->
   dfrd = Q.defer()
   options =
      hostname: hostname
      path: "/videos?page=#{page}&size=10&genre=&sort=MostViewedAllTime&token=#{apiToken}"

   req = https.get options,(res)->
      body =""
      res.on 'data', (chunk)->
         body += chunk

      res.on "end", ->
         ob = JSON.parse body
         dfrd.resolve ob

      req.on "error", (e)->
         console.log "error in request: #{e}"
         dfrd.reject e

   dfrd.promise

###
   Takes raw videos (parsed json array) and makes them easier to use for generating sitemap xml
###
prepareVideosForXml = (videos)->
   vids = []
   for video in videos
      artistSafeName = _.findWhere(video.artists, {"role":"Main"}).urlSafeName
      vids.push
         loc               :  "#{artistSafeName}/#{video.urlSafeName}/#{video.isrc}"
         thumbnail_loc     :  video.thumbnailUrl || ""
         title             :  video.title || ""
         view_count        :  video.views.total || ""
         duration          :  video.duration || ""
         publication_date  :  video.releaseDate || ""
         family_friendly   :  not video.isExplicit
         isrc              :  video.isrc

   vids

###
   Makes a chunk of xml based on videos (previosly prepared collection)
###
generateXmlChunk = (videoInfo, xmlRoot)->
   process.stdout.write " #{videoInfo.isrc}"

   chunk = xmlRoot.ele("url")
      .ele("loc").txt("http://www.vevo.com/watch/#{videoInfo.loc}").up()
      .ele("video:video")
         .ele("video:player_loc")
            .att("allow_embed","yes")
            .att("autoplay","autoplay=1")
            .txt("http://videoplayer.vevo.com/embed/embedded?videoId=#{videoInfo.isrc}&amp;playlist=False&amp;autoplay=0&amp;playerId=62FF0A5C-0D9E-4AC1-AF04-1D9E97EE3961&amp;playerType=embedded")
            .up()
         .ele("video:thumbnail_loc").txt(videoInfo.thumbnail_loc).up()
         .ele("video:title").txt(videoInfo.title).up()
         .ele("video:description").txt(videoInfo.title).up()
         .ele("video:view_count").txt(videoInfo.view_count).up()
         .ele("video:duration").txt(videoInfo.duration).up()
         .ele("video:publication_date").txt(videoInfo.publication_date).up()
         .ele("video:family_friendly").txt(if videoInfo.family_friendly then "Yes" else "No")

   chunk


main = (->
   indexRoot = xmlBuilder.create().begin("sitemapindex").att("xmlns","http://www.sitemaps.org/schemas/sitemap/0.9")
   ct =  # counters
      jsPageNo       : 1
      rowsInFile     : 0
      sitemapIndex   : 0

   # function wraps while loop in a promise
   promiseWhile = (condition, body)->
      dfrd = Q.defer()
      lp = ->
         if !condition() then return dfrd.resolve()

         Q.when body(), lp, dfrd.reject

      Q.nextTick lp
      dfrd.promise

   # let's get an api token first and then proceed to everything else
   Q.when getApiToken(), ->
      siteMapRoot = null
      promiseWhile(->
         ct.jsPageNo isnt -1
      ,->
         console.log "getting page #{ct.jsPageNo}"
         getJsonPage(ct.jsPageNo).then((json)->
            if json.videos.length < 1 # no videos returned
               console.log "no more videos"
               ct.jsPageNo = -1
               return

            if ct.rowsInFile is 0 # starting new sitemapfile
               console.log "creating new sitemap index"
               indexRoot.ele("sitemap").ele("loc").txt("http://www.vevo.com/videos_sitemap_page_#{ct.sitemapIndex}.xml").up().up()
               siteMapRoot = xmlBuilder.create().begin("urlset")
                  .att("xmlns:video","http://www.google.com/schemas/sitemap-video/1.1")
                  .att("xmlns","http://www.sitemaps.org/schemas/sitemap/0.9")

            for vi in prepareVideosForXml(json.videos)
               generateXmlChunk vi, siteMapRoot
               ct.rowsInFile++

               if ct.rowsInFile > 5000
                  console.log "writing into #{ct.sitemapIndex}.xml"
                  fs.writeFile "videos_sitemap_page_#{ct.sitemapIndex}.xml",siteMapRoot.toString({pretty : true}), (err)->
                     console.log if err then err else "videos_sitemap_page_#{ct.sitemapIndex}.xml file was saved"
                  ct.sitemapIndex++
                  ct.rowsInFile = 0


         ).then(->
            ct.jsPageNo++
         )
      ).then ->
         fs.writeFile "videos_sitemap_index.xml",indexRoot.toString({pretty : true}), (err)->
            console.log if err then err else "videos_sitemap_index.xml file was saved"
      .done()

)()