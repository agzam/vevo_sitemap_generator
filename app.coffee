https = require "https"
request = require "request"
fs = require "fs"
Q = require "q"
_ = require "lodash"
XMLWriter = require "xml-writer"

hostname = "stg-apiv2.vevo.com"
apiToken = null

###
 * Gets api token, everytime new
###
getApiToken = ->
   dfrd = Q.defer()

   post_data = JSON.stringify
      "client_id"      : ""
      "client_secret"  : ""
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
 * Gets json data for given path from the api
###
getJsonData = (page, path)->
   dfrd = Q.defer()
   console.log "getting json data, page #{page}"
   options =
      hostname: hostname
      path: path

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
 * Gets videos data from api
###
getVideosJsonPage = (page) ->
   getJsonData(page, "/videos?page=#{page}&size=100&genre=&sort=MostViewedAllTime&token=#{apiToken}")


###
 * Gets artists data from the api
###
getArtistsJsonPage = (page) ->
   getJsonData(page,"/artists?page=#{page}&size=100&token=#{apiToken}")


###
   Takes raw videos (parsed json array) and makes them easier to use for generating sitemap xml
###
prepareVideosForXml = (videos)->
   for video in videos
      mn = _.findWhere(video.artists, {"role":"Main"})

      artistSafeName   =  if mn then mn.urlSafeName || "" else ""
      loc               :  "#{artistSafeName}/#{video.urlSafeName}/#{video.isrc}"
      thumbnail_loc     :  video.thumbnailUrl || ""
      title             :  video.title || ""
      view_count        :  video.views.total || ""
      duration          :  video.duration || ""
      publication_date  :  video.releaseDate || ""
      family_friendly   :  not video.isExplicit
      isrc              :  video.isrc

###
   Takes raw artists (parsed json array) and makes them easier to use for generating sitemap xml
###
prepareArtistsForXml = (artists)->
   for artist in artists
      name              : artist.name or ""
      urlSafeName       : artist.urlSafeName or ""
      thumbnailUrl      : artist.thumbnailUrl or ""

###
   Makes a chunk of xml based on videos (previosly prepared collection)
###
generateVideosXmlChunk = (videoInfo, xmlWriter)->
   console.log videoInfo
   xmlWriter.startElement("url")
      .startElement("loc").text("http://www.vevo.com/watch/#{videoInfo.loc}").endElement()
      .startElement("video:video")
         .startElement("video:player_loc")
            .writeAttribute("allow_embed","yes")
            .writeAttribute("autoplay","autoplay=1")
            .text("http://videoplayer.vevo.com/embed/embedded?videoId=#{videoInfo.isrc}&amp;playlist=False&amp;autoplay=0&amp;playerId=62FF0A5C-0D9E-4AC1-AF04-1D9E97EE3961&amp;playerType=embedded")
         .endElement()
         .startElement("video:thumbnail_loc").text(videoInfo.thumbnail_loc).endElement()
         .startElement("video:title").text(videoInfo.title).endElement()
         .startElement("video:description").text(videoInfo.title).endElement()
         .startElement("video:view_count").text(videoInfo.view_count.toString()).endElement()
         .startElement("video:duration").text(videoInfo.duration.toString()).endElement()
         .startElement("video:publication_date").text(videoInfo.publication_date).endElement()
         .startElement("video:family_friendly").text(if videoInfo.family_friendly then "Yes" else "No").endElement()
      .endElement()
   .endElement()

generateArtistsXmlChunk = (artistInfo, xmlWriter)->
   xmlWriter.startElement("url")
      .startElement("loc").text("http://www.vevo.com/artist/#{artistInfo.urlSafeName}").endElement()
   .endElement()


createNewVideosSitemap = (index, indexMapWriter)->
   console.log "creating new sitemap index #{index}"
   indexMapWriter.startElement("sitemap")
      .startElement("loc").text("http://www.vevo.com/videos_sitemap_page_#{index}.xml").endElement()
      .endElement()

   siteMapWs = fs.createWriteStream "videos_sitemap_page_#{index}.xml"
   siteMapWriter = new XMLWriter true,(string, encoding)-> siteMapWs.write string, encoding
   siteMapWriter.startDocument()
      .startElement("urlset")
      .writeAttribute("xmlns:video","http://www.google.com/schemas/sitemap-video/1.1")
      .writeAttribute("xmlns","http://www.sitemaps.org/schemas/sitemap/0.9")

   siteMapWriter

###
  * While loop wrapped in a promise
###
promiseWhile = (condition, body)->
   dfrd = Q.defer()
   lp = ->
      if !condition() then return dfrd.resolve()

      Q.when body(), lp, dfrd.reject

   Q.nextTick lp
   dfrd.promise

generateSitemapsForVideos = ->

   ct =  # counters
      jsPageNo       : 1
      rowsInFile     : 0
      sitemapIndex   : 0

   # let's get an api token first and then proceed to everything else
   Q.when getApiToken(), ->
      siteMapWriter = null
      indexMapWs = fs.createWriteStream "videos_sitemap_index.xml"
      indexMapWriter = new XMLWriter true,(string, encoding)-> indexMapWs.write string, encoding
      indexMapWriter.startDocument().startElement("sitemapindex")
         .writeAttribute "xmlns","http://www.sitemaps.org/schemas/sitemap/0.9"

      promiseWhile(->
         ct.jsPageNo isnt -1 and ct.jsPageNo isnt 0
      ,->
         getVideosJsonPage(ct.jsPageNo)
         .then((json)->
            if json.videos.length < 1  # no videos returned
               console.log "no more videos"
               ct.jsPageNo = -1
               return

            siteMapWriter = createNewVideosSitemap ct.sitemapIndex, indexMapWriter if ct.rowsInFile is 0 # starting new sitemapfile

            vids = prepareVideosForXml(json.videos)
            console.log "vids length #{vids.length}"
            for vid in vids
               generateVideosXmlChunk vid, siteMapWriter
               ct.rowsInFile++
               if ct.rowsInFile > 10000
                  console.log "writing into videos_sitemap_page_#{ct.sitemapIndex}.xml"
                  siteMapWriter.endElement().endDocument()
                  ct.sitemapIndex++
                  ct.rowsInFile = 0
                  siteMapWriter = createNewVideosSitemap ct.sitemapIndex, indexMapWriter

            ).then(-> ct.jsPageNo++ )
      ).then ->
         console.log(" ending ")
         siteMapWriter.endElement().endDocument()
         indexMapWriter.endElement().endDocument()
      .done()


generateSiteMapsFoArtists = ->
   jsPageNo = 1
   # let's get an api token first and then proceed to everything else
   Q.when getApiToken(), ->
      sitemapWs = fs.createWriteStream "artists_sitemap.xml"
      sitemapWriter = new XMLWriter true,(string, encoding)-> sitemapWs.write string, encoding
      sitemapWriter.startDocument().startElement("sitemapindex")
         .writeAttribute "xmlns","http://www.sitemaps.org/schemas/sitemap/0.9"

      promiseWhile(->
         jsPageNo isnt -1 and jsPageNo isnt 0
      ,->
         getArtistsJsonPage(jsPageNo)
         .then((json)->
            if json.artists.length < 1  # no artists returned
               console.log "no more artists"
               jsPageNo = -1
               return

            artists = prepareArtistsForXml json.artists
            for art in artists
               generateArtistsXmlChunk art, sitemapWriter

         ).then(-> jsPageNo++ )
      ).then ->
         console.log(" ending ")
         sitemapWriter.endElement().endDocument()
      .done()

generateSiteMapsFoArtists()