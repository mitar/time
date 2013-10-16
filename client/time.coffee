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

Meteor.startup ->
  Session.set 'searchResultsCount', undefined

Template.viewer.rendered = ->
  return if @handle

  @node = @find 'svg'
  @handle = Deps.autorun =>
    # TODO

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

    HTTP.get "http://www.quandl.com/api/v1/datasets.json?query=#{ encodeURIComponent query }", (error, result) ->
      if error
        alert error
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
  datasets = _.pluck Datasets.find({}).fetch(), 'code'
  SearchResults.find
    column_names: 'Date' # We limit only to those which have 'Date' as a column
    code:
      $nin: datasets

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
    Datasets.insert
      name: template.data.name
      code: template.data.code
      columns: _.without template.data.column_names, 'Date' # We require all to have 'Date' as a column
      color: color

