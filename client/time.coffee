SearchResults = new Meteor.Collection null

PALETTE = [
  '#1f77b4'
  '#ff7f0e'
  '#2ca02c'
  '#d62728'
  '#9467bd'
  '#8c564b'
  '#e377c2'
  '#7f7f7f'
  '#bcbd22'
  '#17becf'
]
API_KEY = Meteor.settings?.public?.API_KEY

Meteor.startup ->
  Session.set 'searchResultsCount', undefined

apiKeyURL = (url) ->
  return url unless API_KEY

  if url.indexOf('?') isnt -1
    "#{ url }&auth_token=#{ API_KEY }"
  else
    "#{ url }?auth_token=#{ API_KEY }"

class Viewer
  constructor: ->
    @margin =
      top: 10
      right: 10
      bottom: 100
      left: 40
    @margin2 =
      top: 430
      right: 10
      bottom: 20
      left: 40
    @width = 960 - @margin.left - @margin.right
    @height = 500 - @margin.top - @margin.bottom
    @height2 = 500 - @margin2.top - @margin2.bottom

    @x = d3.time.scale().range([0, @width])
    @x2 = d3.time.scale().range([0, @width])
    @y = d3.scale.linear().range([@height, 0])
    @y2 = d3.scale.linear().range([@height2, 0])

    @xAxis = d3.svg.axis().scale(@x).orient('bottom')
    @xAxis2 = d3.svg.axis().scale(@x2).orient('bottom')
    @yAxis = d3.svg.axis().scale(@y).orient('left')

    @brush = d3.svg.brush().x(@x2).on 'brush', =>
      @x.domain(if @brush.empty() then @x2.domain() else @brush.extent())
      @focus.select('path').attr('d', @area)
      @focus.select('.x.axis').call(@xAxis)

Template.viewer.rendered = ->
  return if @handle

  @node = @find '.viewer'
  @viewer = new Viewer()
  @handle = Datasets.find({}).observeChanges
    added: (id, fields) =>
      d3.csv apiKeyURL("http://www.quandl.com/api/v1/datasets/#{ fields.code }.csv"), (error, data) =>
        if error
          alert "Error fetching dataset: #{ error.status } #{ error.statusText }"
          return

        data.forEach (d) =>
          d.Date = moment.utc(d.Date).toDate()

        @viewer.area = d3.svg.area().interpolate('monotone').x(
          (d) => @viewer.x(d.Date)
        ).y0(@viewer.height).y1(
          (d) => @viewer.y(d[fields.selectedColumn])
        )

        @viewer.area2 = d3.svg.area().interpolate('monotone').x(
          (d) => @viewer.x2(d.Date)
        ).y0(@viewer.height2).y1(
          (d) => @viewer.y2(d[fields.selectedColumn])
        )

        svg = d3.select(@node).append('svg').attr(
          'width', @viewer.width + @viewer.margin.left + @viewer.margin.right
        ).attr(
          'height', @viewer.height + @viewer.margin.top + @viewer.margin.bottom
        )

        svg.append("defs").append("clipPath")
            .attr("id", "clip")
          .append("rect")
            .attr("width", @viewer.width)
            .attr("height", @viewer.height)

        @viewer.focus = svg.append("g")
            .attr("transform", "translate(" + @viewer.margin.left + "," + @viewer.margin.top + ")")

        context = svg.append("g")
            .attr("transform", "translate(" + @viewer.margin2.left + "," + @viewer.margin2.top + ")")

        @viewer.x.domain(d3.extent(data.map((d) => d.Date)))
        @viewer.y.domain([0, d3.max(data.map((d) => d[fields.selectedColumn]))])
        @viewer.x2.domain(@viewer.x.domain());
        @viewer.y2.domain(@viewer.y.domain());

        @viewer.focus.append("path")
            .datum(data)
            .attr("clip-path", "url(#clip)")
            .attr("d", @viewer.area)

        @viewer.focus.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + @viewer.height + ")")
            .call(@viewer.xAxis);

        @viewer.focus.append("g")
            .attr("class", "y axis")
            .call(@viewer.yAxis);

        context.append("path")
            .datum(data)
            .attr("d", @viewer.area2)

        context.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + @viewer.height2 + ")")
            .call(@viewer.xAxis2)

        context.append("g")
            .attr("class", "x brush")
            .call(@viewer.brush)
          .selectAll("rect")
            .attr("y", -6)
            .attr("height", @viewer.height2 + 7)

    changed: (id, fields) =>
      color = fields.color

      return unless color

      console.log "color", color

    removed: (id) =>
      console.log "removed", id

Template.viewer.destroyed = ->
  @handle.stop() if @handle

Template.datasets.datasets = ->
  Datasets.find {}

Template.datasetsItem.rendered = ->
  id = @data._id
  $(@find '.color').spectrum(
    showInput: true
    showPalette: true
    showSelectionPalette: false
    showPalette: true,
    palette: _.map PALETTE, (p) -> [p]
    preferredFormat: 'hex'
  ).change (e) ->
    Datasets.update id,
      $set:
        color: $(this).val()

Template.datasetsItem.events =
  'click .remove': (e, template) ->
    e.preventDefault()

    Datasets.remove template.data._id

Template.search.events =
  'submit .search-form': (e, template) ->
    e.preventDefault()

    query = $(template.find '.query').val()

    return unless query

    Session.set 'searchResultsCount', undefined
    SearchResults.remove {}

    HTTP.get apiKeyURL("http://www.quandl.com/api/v1/datasets.json?query=#{ encodeURIComponent query }"), (error, result) ->
      if error
        alert "Error fetching search results: #{ error }"
        return

      if not result.data
        Session.set 'searchResultsCount', 0
        return

      Session.set 'searchResultsCount', result.data.total_count

      for d in result.data.docs
        SearchResults.insert d

Template.searchResults.active = ->
  _.isFinite Session.get 'searchResultsCount'

Template.searchResults.searchResults = ->
  ids = _.pluck Datasets.find({}).fetch(), 'foreignId'
  SearchResults.find
    column_names: 'Date' # We limit only to those which have 'Date' as a column
    id:
      $nin: ids

Template.searchResults.searchResultsCount = ->
  Session.get 'searchResultsCount'

Template.searchResultsCount.searchResultsCount = Template.searchResults.searchResultsCount

Template.searchResultsCount.searchResultsShown = ->
  Template.searchResults.searchResults().count()

Template.searchResultsItem.columns = (columnNames) ->
  columnNames.join ', '

randomColor = ->
  '#' + Math.floor(Math.random() * 16777216).toString(16)

Template.searchResultsItem.events =
  'click .add-dataset-button': (e, template) ->
    colors = _.pluck Datasets.find({}).fetch(), 'color'
    unique = _.difference PALETTE, colors
    color = if unique.length then unique[0] else randomColor()
    columns = _.without template.data.column_names, 'Date' # We require all to have 'Date' as a column
    Datasets.insert
      foreignId: template.data.id
      name: template.data.name
      code: "#{ template.data.source_code}/#{ template.data.code }"
      columns: columns
      selectedColumn: columns[0]
      color: color

