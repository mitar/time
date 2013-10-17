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

datasets = {}

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
      return

      # TODO
      @x.domain(if @brush.empty() then @x2.domain() else @brush.extent())
      @focus.select('path').attr('d', @line)
      @focus.select('.x.axis').call(@xAxis)

    @datesExtent = []
    @ysExtent = []

  computeLines: (id) =>
    datasets[id].line = d3.svg.line().interpolate('monotone').x(
      (d) => @x(d.Date)
    ).y(
      (d) => @y(d[datasets[id].fields.selectedColumn])
    )

    datasets[id].line2 = d3.svg.line().interpolate('monotone').x(
      (d) => @x2(d.Date)
    ).y(
      (d) => @y2(d[datasets[id].fields.selectedColumn])
    )

  computeNewExtent: (id) =>
    newDatesExtend = d3.extent datasets[id].data.map((d) => d.Date)
    @datesExtent = d3.extent(@datesExtent.concat newDatesExtend...)

    newYsExtent = d3.extent datasets[id].data.map((d) => d[datasets[id].fields.selectedColumn])
    @ysExtent = d3.extent(@ysExtent.concat newYsExtent...)

    if @ysExtent[0] > 0
      @ysExtent[0] = 0

  computeExtents: =>
    @datesExtent = []
    @ysExtent = []

    for id of datasets
      @computeNewExtent id

  resetDomains: =>
    @x.domain(@datesExtent)
    @y.domain(@ysExtent)
    @x2.domain(@x.domain())
    @y2.domain(@y.domain())

  resetAxes: =>
    @focus.selectAll('g').remove()

    @context.selectAll('g').remove()

    return if _.isEmpty datasets

    @focus.append('g').attr('class', 'x axis').attr('transform', 'translate(0,' + @height + ')').call(@xAxis)

    @focus.append('g').attr('class', 'y axis').call(@yAxis)

    @context.append('g').attr('class', 'x axis').attr('transform', 'translate(0,' + @height2 + ')').call(@xAxis2)

  resetLines: =>
    for id, dataset of datasets
      dataset.focusPath.attr('d', dataset.line)
      dataset.contextPath.attr('d', dataset.line2)

  addedDataset: (id) =>
    return unless datasets[id]

    @computeLines id

    @computeNewExtent id

    @resetDomains()

    datasets[id].focusPath = @focus.append('path').datum(datasets[id].data).attr('clip-path', 'url(#clip)').style('stroke', datasets[id].fields.color)

    datasets[id].contextPath = @context.append('path').datum(datasets[id].data).style('stroke', datasets[id].fields.color)

    @resetAxes()

    @resetLines()

    #@context.append('g').attr('class', 'x brush').call(@brush)
    #  .selectAll('rect').attr('y', -6).attr('height', @height2 + 7)

  removedDataset: (id, dataset) =>
    return if datasets[id]

    @computeExtents()

    @resetDomains()

    dataset.focusPath.remove()
    dataset.contextPath.remove()

    @resetAxes()

    @resetLines()

  changeColor: (id) =>
    return unless datasets[id]

    datasets[id].focusPath.style('stroke', datasets[id].fields.color)
    datasets[id].contextPath.style('stroke', datasets[id].fields.color)

  changeSelectedColumn: (id) =>
    return unless datasets[id]

    @computeLines id

    @computeExtents()

    @resetDomains()

    @resetAxes()

    @resetLines()

Template.viewer.rendered = ->
  return if @handle

  @node = @find '.viewer'
  @viewer = new Viewer()

  @viewer.svg = d3.select(@node).append('svg').attr(
    'width', @viewer.width + @viewer.margin.left + @viewer.margin.right
  ).attr(
    'height', @viewer.height + @viewer.margin.top + @viewer.margin.bottom
  )

  @viewer.svg.append('defs').append('clipPath').attr('id', 'clip')
    .append('rect').attr('width', @viewer.width).attr('height', @viewer.height)

  @viewer.focus = @viewer.svg.append('g')
    .attr('transform', 'translate(' + @viewer.margin.left + ',' + @viewer.margin.top + ')')

  @viewer.context = @viewer.svg.append('g')
    .attr('transform', 'translate(' + @viewer.margin2.left + ',' + @viewer.margin2.top + ')')
  
  @handle = Datasets.find({}).observeChanges
    added: (id, fields) =>
      d3.csv apiKeyURL("http://www.quandl.com/api/v1/datasets/#{ fields.code }.csv"), (error, data) =>
        if error
          alert "Error fetching dataset: #{ error.status } #{ error.statusText }"
          return

        for d in data
          d.Date = moment.utc(d.Date).toDate()
          for name, value of d when name isnt 'Date'
            d[name] = +value

        datasets[id] =
          data: data
          fields: fields

        @viewer.addedDataset id

    changed: (id, fields) =>
      if fields.color
        datasets[id].fields.color = fields.color
        @viewer.changeColor id
      if fields.selectedColumn
        datasets[id].fields.selectedColumn = fields.selectedColumn
        @viewer.changeSelectedColumn id

    removed: (id) =>
      if datasets[id]
        dataset = datasets[id]
        delete datasets[id]
        @viewer.removedDataset id, dataset

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

    Datasets.remove @_id

Template.datasetsItemColumns.events =
  'change .datasets-item-columns': (e, template) ->
    Datasets.update @_id,
      $set:
        selectedColumn: $(e.currentTarget).val()

Template.datasetsItemColumns.columns = ->
  for c in @columns
    name: c
    selected: 'selected="selected"' if c is @selectedColumn

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
    columns = _.without @column_names, 'Date' # We require all to have 'Date' as a column
    Datasets.insert
      foreignId: @id
      name: @name
      code: "#{ @source_code}/#{ @code }"
      columns: columns
      selectedColumn: columns[0]
      color: color

