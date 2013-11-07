// Generated by CoffeeScript 1.6.3
(function() {
  var Q, generateXmlChunk, getJsonPage, http, main, prepareVideosForXml, xmlBuilder, xmlRoot, _;

  http = require("https");

  Q = require("q");

  _ = require("lodash");

  xmlBuilder = require("xmlbuilder");

  getJsonPage = function(page) {
    var dfrd, options, req;
    dfrd = Q.defer();
    options = {
      hostname: "stg-apiv2.vevo.com",
      path: "/videos?page=" + page + "&size=10&genre=&sort=MostViewedAllTime&token=_TMw_fGgJHvzr84MqwK1eWhBgbdebZhAm_y3W1ou-sU1.W_lW2AmcGNcfZlz4EsWeeWPIgFcjYTSgnIRkqmJNbl57hMKTYfvwzFYAjoahrfulhngROA2"
    };
    req = http.get(options, function(res) {
      var body;
      body = "";
      res.on('data', function(chunk) {
        return body += chunk;
      });
      res.on("end", function() {
        var ob;
        ob = JSON.parse(body);
        return dfrd.resolve(ob);
      });
      return req.on("error", function(e) {
        return dfrd.reject(e);
      });
    });
    return dfrd.promise;
  };

  prepareVideosForXml = function(videos) {
    var artistSafeName, video, vids, _i, _len;
    vids = [];
    for (_i = 0, _len = videos.length; _i < _len; _i++) {
      video = videos[_i];
      artistSafeName = _.findWhere(video.artists, {
        "role": "Main"
      }).urlSafeName;
      vids.push({
        loc: "" + artistSafeName + "/" + video.urlSafeName + "/" + video.isrc,
        thumbnail_loc: video.thumbnailUrl,
        title: video.title,
        view_count: video.views.total,
        duration: video.duration,
        publication_date: video.releaseDate,
        family_friendly: !video.isExplicit,
        isrc: video.isrc
      });
    }
    return vids;
  };

  generateXmlChunk = function(videoInfo) {
    var chunk;
    chunk = xmlRoot.ele("url").ele("loc").txt("http://www.vevo.com/watch/" + videoInfo.loc).up().ele("video:video").ele("video:player_loc").att("allow_embed", "yes").att("autoplay", "autoplay=1").txt("http://videoplayer.vevo.com/embed/embedded?videoId=" + videoInfo.isrc + "&amp;playlist=False&amp;autoplay=0&amp;playerId=62FF0A5C-0D9E-4AC1-AF04-1D9E97EE3961&amp;playerType=embedded").up().ele("video:thumbnail_loc").txt(videoInfo.thumbnail_loc).up().ele("video:title").txt(videoInfo.title).up().ele("video:description").txt(videoInfo.title).up().ele("video:view_count").txt(videoInfo.view_count).up().ele("video:duration").txt(videoInfo.duration).up().ele("video:publication_date").txt(videoInfo.publication_date).up().ele("video:family_friendly").txt(videoInfo.family_friendly ? "Yes" : "No");
    return chunk;
  };

  xmlRoot = null;

  main = (function() {
    var doc;
    doc = xmlBuilder.create();
    xmlRoot = doc.begin("");
    return getJsonPage(1).then(function(json) {
      var vi, _i, _len, _ref;
      _ref = prepareVideosForXml(json.videos);
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        vi = _ref[_i];
        generateXmlChunk(vi);
      }
      return console.log(doc.toString({
        pretty: true
      }));
    });
  })();

}).call(this);

/*
//@ sourceMappingURL=app.map
*/
