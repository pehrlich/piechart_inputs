Array.prototype.first = ->
  @[0]

String.prototype.to_i = ->
  parseInt(@, 10)

Number.prototype.round = (digits = 0)->
  factor = Math.pow(10, digits)
  Math.round(this * factor) / factor


Number.prototype.to_degrees = ->
  this * 180 / Math.PI

Number.prototype.to_radians = ->
  this / 180 * Math.PI

# holds pie edges.  Does not interface at all with dom or rendering
# @value is the sum of all the slices
class Pie
  constructor: (@edges = [], @value = 0, @baseAngle = 0)->

  addEdge: (value)->
    @edges.push new Pie::Edge(@, value, @edges.length)
    @value += value

  # returns the last-added edge with a value greater than zero
  lastEdge: ->
    # we slice in order to duplicate the object
    for edge in @edges.slice(0).reverse()
      return edge if edge.value

  getEdge: (i)->
    if i < 0 then i += @edges.length
    @edges[i % @edges.length]

  # returns the angle between two angles, in degrees
  dAngle: (a, b)->
    d = a - b
    d -= 360 if d > 180
    d += 360 if d < -180
    d

  getClosestEdge: (goal_angle)->
    best = @edges[0]
    for edge in @edges
      if Math.abs(@dAngle(goal_angle, edge.getAngle())) < Math.abs(@dAngle(goal_angle, best.getAngle()))
        best = edge
    best

  # accepts an angle and optionally an edge to move.
  # if no edge given, the edge closest to the given angle will be used.
  # returns the edge used.
  setAngle: (new_angle, edge)->
    edge ||= @getClosestEdge(new_angle)
    dangle = @dAngle(new_angle, edge.getAngle())
    direction = if dangle > 0 then 'CW' else 'CCW'
    edge.changeAngle(dangle, direction, true)
    edge.nextEdge('CW').changeAngle(-dangle, 'CW')
    edge

  getValues: ->
    @edges.map (edge) -> edge.value


class Pie::Edge
  constructor: (@pie, @value, @myIndex)->

  nextEdge: (direction)->
    if direction == 'CCW'
      @pie.getEdge @myIndex - 1
    else
      @pie.getEdge @myIndex + 1

  previousEdge: (direction)->
    if direction == 'CW'
      @pie.getEdge @myIndex - 1
    else
      @pie.getEdge @myIndex + 1

  getAngle: ->
    if @ == @pie.edges.first()
      baseAngle = @pie.baseAngle
    else
      baseAngle = @nextEdge('CCW').getAngle()
    baseAngle + @sliceWidth() % 360

  # returns the angle of the pie slice, in degrees?
  sliceWidth: ->
    @value / @pie.value * 360

  # changes the width of the slice by dAngle.
  # updates its @value, which can then be used in rendering
  # if dAngle is negative and larger than the width of the slice,
  # direction is used to choose a neighboring slice to subtract from.
  # updateBase is used to allow the base 0° angle to be changed by the edge
  changeAngle: (dAngle, direction, updateBase = false)->
    #    console.log "changing edge #{@myIndex} angle by #{dangle} #{direction}"
    slice_width = @sliceWidth()
    if (-dAngle) > slice_width
      console.log "dAngle greater than slice width by #{difference}: #{dAngle} #{slice_width}"
      difference = slice_width + dAngle
      # for large negative angles, bump to the next edge
      @value = 0
      @nextEdge(direction).changeAngle(difference, direction, updateBase)
      dAngle = -slice_width
    else
      console.log "value, next value #{@value} #{@nextEdge(direction).value}"
      @value += (dAngle / 360) * @pie.value

    if updateBase && @ == @pie.lastEdge()
      console.log "update base #{dAngle}"
      @pie.baseAngle += dAngle

    if @value > @pie.value
      console.log "Warning: edge #{@myIndex} new value too large: #{@value} > #{@pie.value}"
      @value = @pie.value

# handles all dom interaction (d3, inputs, and so on)
# Markup should consist of any element with multiple hidden inputs inside of it.
# Each of these hidden elements will represent a pie slice, and be updated live.
# Will fill the given element as completely as possible, while remaining circular.
# accepts options:
# label_radius: number of pixels inside from the outter edge of the pie to place the numbers.  Negative values OK.  Default: 40
# label_prefix: String prefix for all labels.  Default: '$'
# label_suffix: String suffix for all labels.  Default: ''
# color: color scheme for the pie slices.  Should accept an integer and return anything accepted by the 'fill' attribute.  Default: d3.scale.category20()
# display_accuracy: Number of decimals to show over the pie slices.  Default: 2
# output_accuracy: Number of decimals to put in to the field inputs.  Default: 2

$.fn.pie = (options = {})->
  element = @get(0)
  pie = new Pie()
  @data({pie: pie})

  defaults = {
    label_radius: 40
    label_prefix: '$'
    label_suffix: ''
    color: d3.scale.category20()
    display_accuracy: 2
    output_accuracy: 2
  }
  $.extend(options, defaults)

  @find('input').each (i, el)->
    pie.addEdge $(el).val().to_i()

  middle = {
    x: this.width() / 2
    y: this.height() / 2
  }
  radius = Math.min(middle.x, middle.y)
  donut = d3.layout.pie().sort(null)
  donut.heading = (degrees)->
    @startAngle(degrees.to_radians())
    @endAngle((degrees + 360).to_radians())

  arc = d3.svg.arc().innerRadius(0).outerRadius(radius)
  label_arc = d3.svg.arc().innerRadius(radius - options.label_radius).outerRadius(radius - options.label_radius)

  svg = d3.select(element)
    .append("svg:svg")
    .attr("width", middle.x * 2)
    .attr("height", middle.y * 2)
    .append("svg:g")
    .attr("transform", "translate(#{middle.x},#{middle.y})")


  # initialize arcs:
  data = pie.getValues()

  gs = svg.selectAll("g")
    .data(donut(data))
    .enter()
    .append("svg:g")

  arcs = gs
    .append("svg:path")
    .attr("fill",(d, i) -> return options.color(i)
    ).attr("d", arc)
    .each((d) ->
      this._current = d
    )

  labels = gs
    .append('svg:text')
    .attr("text-anchor", "middle")



  click_angle = (e)->
    position_to_angle(e.offsetX - middle.x, middle.y - e.offsetY)

  touch_angle = (e)->
#    alert position_to_angle
    position_to_angle(e.originalEvent.touches[0].clientX - middle.x, middle.y - e.originalEvent.touches[0].clientY)

  position_to_angle = (dx, dy)=>
    mouse_angle = Math.atan(dx / dy).to_degrees()

    if dy < 0
      # bottom
      mouse_angle = 180 + mouse_angle
    if dy >= 0 && dx < 0
      # top left
      mouse_angle = 360 + mouse_angle
    mouse_angle


  # these must be initialized before setAngle for scoping
  mouse_angle = undefined
  selected_edge = null

  # inputs wrapped by d3.js for live updating
  inputs = d3.select(element).selectAll('input')

  setAngle = (degrees, animate = false)->
    return if mouse_angle == degrees

    mouse_angle = degrees
    if selected_edge
      pie.setAngle(mouse_angle, selected_edge)
    else
      selected_edge = pie.setAngle(mouse_angle)

    arc_data = donut.heading(pie.baseAngle)(pie.getValues())
    arcs.data(arc_data).transition().duration(0).attrTween("d", arcTween)
    labels.data( arc_data ).attr("transform", (d)->
      "translate(#{ label_arc.centroid(d) })"
    ).text (d)->
      options.label_prefix + d.value.round(options.display_accuracy) + options.label_suffix

    inputs.data(arc_data).attr 'value', (d)-> d.value.round(options.output_accuracy)


  arcTween = (datum, i, a) ->
    interpolator = d3.interpolate(this._current, datum)
    this._current = interpolator(0)
    return (t) ->
      return arc(interpolator(t))

  # initialize labels:
  setAngle pie.baseAngle
  mouse_angle = undefined
  selected_edge = null


  @on 'mousedown', (e)->
    setAngle click_angle(e)

  # to have dragging work when not hovering over the element, bind to document here instead
  @on 'mousemove', (e)->
    return unless selected_edge
    setAngle click_angle(e)

  $(document).on 'mouseup', (e)->
    setAngle click_angle(e)
    selected_edge = null

  @on 'touchstart', (e)->
    setAngle touch_angle(e)

  @on 'touchmove', (e)->
    e.preventDefault();
    return unless selected_edge
    setAngle touch_angle(e)

  @on 'touchend', (e)->
    setAngle touch_angle(e)
    selected_edge = null


