http = require "https"
Q = require "q"
_ = require "lodash"
xmlBuilder = require "xmlbuilder"


getJsonPage = (page) ->
   dfrd = Q.defer()

   options =
      hostname: "stg-apiv2.vevo.com"
      path: "/videos?page=#{page}&size=10&genre=&sort=MostViewedAllTime&token=_TMw_fGgJHvzr84MqwK1eWhBgbdebZhAm_y3W1ou-sU1.W_lW2AmcGNcfZlz4EsWeeWPIgFcjYTSgnIRkqmJNbl57hMKTYfvwzFYAjoahrfulhngROA2"

   req = http.get options,(res)->
      body =""
      res.on 'data', (chunk)->
         body += chunk
      res.on "end", ->
         ob = JSON.parse body
         dfrd.resolve ob

      req.on "error", (e)->
         dfrd.reject e

   dfrd.promise


prepareVideosForXml = (videos)->
   vids = []
   for video in videos
      artistSafeName = _.findWhere(video.artists, {"role":"Main"}).urlSafeName
      vids.push
         loc               :  "#{artistSafeName}/#{video.urlSafeName}/#{video.isrc}"
         thumbnail_loc     :  video.thumbnailUrl
         title             :  video.title
         view_count        :  video.views.total
         duration          :  video.duration
         publication_date  :  video.releaseDate
         family_friendly   :  not video.isExplicit
         isrc              :  video.isrc

   vids

generateXmlChunk = (videoInfo)->
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

xmlRoot = null

main = (->
   doc = xmlBuilder.create()

   xmlRoot = doc.begin("")
#      doc.begin("urlset")
#      .att("xmlns:video","http://www.google.com/schemas/sitemap-video/1.1")
#      .att("xmlns","http://www.sitemaps.org/schemas/sitemap/0.9")

   getJsonPage(1).then (json)->
      for vi in prepareVideosForXml(json.videos)
         generateXmlChunk(vi)

      console.log doc.toString {pretty:true}

)()