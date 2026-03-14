"use strict";

// disable JSHint warning: Use the function form of "use strict".
// This warning is meant to prevent problems when concatenating scripts that
// aren't strict, but we shouldn't have any of those anyway.
/* jshint -W097 */

/// Global variables

// map< file name/path, position of fileinfo in fileJSON array (which is
// the same as the tab index)>
// i.e. map< file name/path, tab index >
var fileIndexMap = {};
var FLOWS = {
    NONE:   0,
    OPENCL: 1,
    HLS:    2,
    BOTH:   3
    };
var VIEWS = {
    NONE:        { value: 0, name: "",                         hash: "",       flow: FLOWS.NONE},
    SUMMARY:     { value: 1, name: "Summary",                  hash: "#view1", flow: FLOWS.BOTH},
    OPT:         { value: 2, name: "Loops analysis",           hash: "#view2", flow: FLOWS.BOTH},
    AREA_SYS:    { value: 3, name: "Area analysis of system",  hash: "#view3", flow: FLOWS.BOTH},
    AREA_SRC:    { value: 4, name: "Area analysis of source",  hash: "#view4", flow: FLOWS.BOTH},
    SPV:         { value: 5, name: "System viewer",            hash: "#view5", flow: FLOWS.OPENCL},
    CSPV:        { value: 5, name: "Component viewer",         hash: "#view5", flow: FLOWS.HLS},
    LMEM:        { value: 6, name: "memory viewer",            hash: "#view6", flow: FLOWS.BOTH},
    VERIF:       { value: 7, name: "Verification statistics",  hash: "#view7", flow: FLOWS.HLS},
    II:          { value: 8, name: "II Estimator",             hash: "#view8", flow: FLOWS.NONE}, // TODO: change to correct flow once activated
    DOT:         { value: 9, name: "Dot graph viewer (alpha)", hash: "#dot",   flow: FLOWS.BOTH}
    };
var viewHash = []; // initialized in main::initializeViews()

// vector< fileInfo objects >
var detailValues = [""];
var detailIndex = 0;
var curFile;
var spv_graph;
var lmem_graph;
var cspv_graph;
var detailOptValues = [];

var spv;
var sideCollapsed = false;
var detailCollapsed = false;
var view = VIEWS.SUMMARY;
var flow = FLOWS.BOTH;
var currentPane = null;

var LOOP_ANALYSIS_NAME = VIEWS.OPT.name + "<span style='float:right'><input id='showFullyUnrolled' type='checkbox' checked='checked' value='Fully unrolled loops'>&nbspShow fully unrolled loops&nbsp</span>";
var REPORT_PANE_HTML = "<div class='classWithPad' id='opt-area-panel'><div class='panel panel-default' id='report-panel-body'><div class='panel-heading'>";
var NO_SOURCE = "No Source Line";
var GRAPH_LOADING_DIV = "<div id='graph_loading' style='height:150px;width:100%;display:table;text-align:center;'>" +
                         "<span style='vertical-align:middle;display:table-cell;'>Loading...</span></div>";

var isValidLoopAnalysis  = true;
var isValidVerifAnalysis = true;
var isValidAreaReport    = true;
var isValidAreaSRCReport = true;
var isValidSystemViewer  = true;
var isValidMemoryViewer  = true;
var isValidFileList      = true;
var isValidSummary       = true;
var isValidWarnings      = true;
var isValidInfo          = true;
var isValidQuartus       = true;
var isValidDot           = true;

function
main()
{
    // check if all information is valid
    isValidLoopAnalysis  = (typeof loopsJSON   != "undefined") && (loopsJSON   = tryParseJSON(loopsJSON))   !== null;
    isValidVerifAnalysis = (typeof verifJSON   != "undefined") && (verifJSON   = tryParseJSON(verifJSON))   !== null;
    isValidAreaReport    = (typeof areaJSON    != "undefined") && (areaJSON    = tryParseJSON(areaJSON))    !== null;
    isValidAreaSRCReport = (typeof area_srcJSON!= "undefined") && (area_srcJSON= tryParseJSON(area_srcJSON))!== null;
    isValidSystemViewer  = (typeof mavJSON     != "undefined") && (mavJSON     = tryParseJSON(mavJSON))     !== null;
    isValidFileList      = (typeof fileJSON    != "undefined") && (fileJSON    = tryParseJSON(fileJSON))    !== null;
    isValidSummary       = (typeof summaryJSON != "undefined") && (summaryJSON = tryParseJSON(summaryJSON)) !== null;
    isValidWarnings      = (typeof warningsJSON!= "undefined") && (warningsJSON= tryParseJSON(warningsJSON))!== null;
    isValidInfo          = (typeof infoJSON    != "undefined") && (infoJSON    = tryParseJSON(infoJSON))    !== null;
    isValidQuartus       = (typeof quartusJSON != "undefined") && (quartusJSON = tryParseJSON(quartusJSON)) !== null;
    isValidMemoryViewer  = (typeof lmvJSON     != "undefined") && (lmvJSON     = tryParseJSON(lmvJSON))     !== null;
    isValidDot           = (typeof enable_dot  != "undefined") && enable_dot == 1;
    if (!isValidDot) VIEWS.DOT.flow = FLOWS.NONE;

    // Set page title
    // TODO: need to update when info.json gets new schema
    var pageTitle = "Report";
    if (isValidInfo && infoJSON.hasOwnProperty('rows')) {
        for (var r = 0; r < infoJSON.rows.length; ++r) {
            if (infoJSON.rows[r].hasOwnProperty('name')) {
                if (infoJSON.rows[r].name === "Project Name") {
                    pageTitle += ": " + infoJSON.rows[r].data;
                } else if (infoJSON.rows[r].name.indexOf("i++") >= 0) {
                    flow = FLOWS.HLS;
                } else if (infoJSON.rows[r].name.indexOf("AOC") >= 0) {
                    flow = FLOWS.OPENCL;
                }
            }
        }
    }
    $('#titleText').html(pageTitle);

    // remove unused/invalid views
    removeInvalidViews();

    // Get area and optimization report
    if (VIEWS.AREA_SYS) {
      VIEWS.AREA_SYS.source = isValidAreaReport ? parseAreaData(areaJSON) : "&nbsp;Area report data is invalid!";
    }
    if (VIEWS.AREA_SRC) {
      VIEWS.AREA_SRC.source = isValidAreaSRCReport ? parseAreaData(area_srcJSON) : "&nbsp;Area report data is invalid!";
    }

    if (VIEWS.SUMMARY) {
        if (isValidSummary && isValidInfo && isValidWarnings) {
            if (isValidQuartus) {
                VIEWS.SUMMARY.source = parseSummaryData(infoJSON, warningsJSON, summaryJSON, quartusJSON);
            } else {
                VIEWS.SUMMARY.source = parseSummaryData(infoJSON, warningsJSON, summaryJSON, undefined);
            }
        } else {
            VIEWS.SUMMARY.source = "&nbspSummary data is invalid!";
        }
    }

    if (VIEWS.OPT) {
        if (isValidLoopAnalysis) {
            VIEWS.OPT.source = parseLoopData(loopsJSON);
        } else {
            VIEWS.OPT.source = "&nbspLoop analysis data is invalid!";
        }
    }

    if (VIEWS.VERIF) {
        if (isValidVerifAnalysis) {
            VIEWS.VERIF.source = parseVerifData(verifJSON);
        } else {
            VIEWS.VERIF.source = "&nbspVerification analysis data is unavailable!\n";
            VIEWS.VERIF.source += "Run the verification testbench to generate this information.";
        }
    }

    if (isValidDot) {
      VIEWS.DOT.source = "<div id='svg_container' style='width:100%;height:100%;margin:0 auto;overflow:hidden;'></div>";
    }

    initializeViews();

    if (isValidFileList) {
      // Add file tabs to the editor pane
      addFileTabs( fileJSON );
      adjustToWindowEvent();
    } else {
      $('#editor-pane').toggle();
      $('#report-pane').css('width', '100%');
      sideCollapsed = true;
      adjustToWindowEvent();
    }

    ///// Functions

    /// main::initializeViews()
    function initializeViews() {
        // create a div for each view, and set it to "hidden"; also create
        // a menu entry for each view
        Object.keys(VIEWS).forEach(function(v) {
            var index = VIEWS[v];
            if (index.name !== "") {
                $("#report-pane")[0].insertAdjacentHTML("beforeend", "<div id=\"report-pane-view" + index.value + "\" class=\"report-pane-view-style\"></div>");
                $("#report-pane-view" + index.value).toggle();
                var li = "<li class=\"dropdown_nav\" viewId=" + v + "><a href=\"";
                if (index == VIEWS.DOT) {
                  // This allows us to update the DOT viewer hash dynamically
                  li += index.hash + "/" + dot_top + "\" id=\"dot_viewer_dropdown_nav\" ";
                } else {
                  li += index.hash + "\" ";
                }
                li += "style='color:black'>" + index.name + "</a></li>";
                $("#view-menu")[0].insertAdjacentHTML("beforeend", li);
            }
            viewHash[index.hash] = v;
            addReportColumn(index);
        });

        // display the current view
        currentPane = "#report-pane-view" + view.value;
        $(currentPane).toggle();
    }

    /// main::addFileTabs
    function
    addFileTabs( fileJSON )
    {
    var navTabs = d3.select( "#editor-pane" ).selectAll( "#editor-pane-nav" );
    var listElements = navTabs.selectAll( "li" )
        .data( fileJSON )
        .enter()
        .append( "li" )
        .attr( "class", function( d, i ) {
            var classname = "";
            if (i === 0) {
                classname = "active";
                $('.selected').html(d.name);
                $('.mouseoverbuttontext').html(d.absName);
                curFile = d.path;
            }
            if(d.has_active_debug_locs) {
              classname += " has_active_debug_locs";
            }
            fileIndexMap[d.path] = i;
            return classname;
        });

    var anchors = listElements
        .append( "a" )
        .attr( "class", "mouseover")
        .attr( "data-target", function( d, i ) { return "#file" + i; } )
        .text( function( d ) { return d.name; });

    //show file path information using hover text
    anchors = listElements
        .append( "p" )
        .attr( "class", "mouseovertext")
        .text( function( d ) {
          return d.absName;
        });

    $( "#editor-pane-nav" ).on( "click", "a", function( e ) {
        $(this).tab("show");
        $("#editor-pane-nav li").removeClass("active");
        $(this).attr("class", "active");

        $('.selected').html($(this).text());
        $('.mouseoverbuttontext').html($(this).next()[0].innerHTML);
    });

    var divs = d3.select( "#editor-pane" ).selectAll( ".tab-content" )
        .selectAll( "div" )
        .data( fileJSON )
        .enter()
        .append( "div" )
        .attr( "class", function( d, i ) {
            var classname = "tab-pane";
            if ( i === 0 ) classname = classname + " in active";
            return classname;
        })
        .attr( "id", function( d, i ) { return "file" + i; } )
        .attr( "style", "height:500px;" );

    var editorDivs = divs
        .append( "div" )
        .attr( "class", "well" );

    editorDivs.each( SetupEditor );

    /// Functions
    function
    SetupEditor( fileInfo )
    {
        var editor = ace.edit( this ); // "this" is the DOM element
        fileInfo.editor = editor;

        editor.setTheme( "../ace/theme/xcode" );
        editor.setFontSize( 12 );
        editor.getSession().setMode( "../ace/mode/c_cpp" );
        editor.getSession().setUseWrapMode( true );
        editor.getSession().setNewLineMode( "unix" );

        // Replace \r\n with \n in the file content (for windows)
        editor.setValue( fileInfo.content.replace( /(\r\n)/gm, "\n" ) );
        editor.setReadOnly( true );
        editor.scrollToLine( 1, true, true, function() {} );
        editor.gotoLine( 1 );
    }
  }
}

///// Global functions


// Global variables for the dot graph viewer.
var dot_editor = null;
var dot_clickdown = null;

// Get the current hierarchy and display it on the view titlebar.
function updateDotHierarchy() {
  var hash = window.location.hash;
  var hash_split = hash.split("/");
  var hierarchy = "";
  if (view == VIEWS.DOT) {
    for (var i = 1; i < hash_split.length; i++) {
      hierarchy += "|" + hash_split[i].replace(/\d+_/, '');
    }
  }
  $("#dot_hierarchy_text").html(hierarchy);
}

// Add the passed-in HDL filename to the source code pane, and display it,
// creating a new ACE editor object if necessary.
function addHdlFileToEditor(file) {
  var rawFile = new XMLHttpRequest();
  rawFile.open("GET", file, false);
  rawFile.onreadystatechange = function () {
    if(rawFile.readyState === 4) {
      if(rawFile.status === 200 || rawFile.status === 0) {
        var allText = rawFile.responseText;

        // Create the editor if it doesn't exist
        if (dot_editor === null) {
          var count = $("#editor-pane-nav li").length;
          $("#editor-pane-nav").append("<li><a data-target='#file" + count + "'>HDL</a><p></p></li>");
          fileIndexMap.HDL = count;

          var editor_div = "<div class='tab-pane' id='file" + count + "' style='height:500px;'>";
          editor_div += "<div class='well' id='dot_editor_well'></div></div>";
          $("#editor-pane .tab-content").append(editor_div);

          dot_editor = ace.edit($("#dot_editor_well")[0]);
          dot_editor.setTheme( "../ace/theme/xcode" );
          dot_editor.setFontSize( 12 );
          dot_editor.getSession().setUseWrapMode( true );
          dot_editor.getSession().setNewLineMode( "unix" );

          fileJSON.push({"editor":dot_editor, "absName":"HDL", "name":"HDL", "path":"HDL", "content":allText});
        }

        // Set the file content
        if (file.endsWith(".vhd")) {
          dot_editor.getSession().setMode( "../ace/mode/vhdl" );
        } else {
          dot_editor.getSession().setMode( "../ace/mode/verilog" );
        }
        dot_editor.setValue( allText.replace( /(\r\n)/gm, "\n" ) );
        dot_editor.setReadOnly( true );

        syncEditorPaneToLine(1, "HDL");
      } else {
        alert("Something went wrong trying to get HDL file", file);
      }
    }
  };
  rawFile.send(null);
}

// Update the page hash to force the 'onhashchange' event handler to call
// goToView, which should then invoke putSvg
function goToDot(dot_hash) {
    $("#dot_viewer_dropdown_nav").attr("href", dot_hash);
    window.location.hash = dot_hash;
}

// Load and display the specified SVG.
function putSvg(next) {
    if (next == VIEWS.DOT.hash) {
      goToDot(next + "/" + dot_top);
      return;
    }
    if (!next) next = dot_top;
    var root = d3.select("#svg_container");
    d3.xml("lib/dot_svg/" + next + ".svg", function(error, documentFragment) {
         if (error) {console.log(error); return;}
         var svgNode = documentFragment.getElementsByTagName("svg")[0];

         var w = $(root.node()).width();
         var h = $(root.node()).height();

         svgNode.setAttribute("viewBox", "0 0 " + w + ' ' + h);
         svgNode.style.width = w;
         svgNode.style.height = h;

         var d = d3.select(svgNode);

         if (root.node().childNodes.length > 0) {
             root.node().replaceChild(svgNode, root.node().childNodes[0]);
         } else {
             root.node().appendChild(svgNode);
         }
         var matrix = d.select("g").node().transform.baseVal.consolidate().matrix;
         var X = matrix.e;
         var Y = matrix.f;
         var width = parseInt(svgNode.getAttribute("width"), 10);
         var height = parseInt(svgNode.getAttribute("height"), 10);
         var x_scale = w / width;
         var y_scale = h / height;
         var initial_scale = Math.min(x_scale, y_scale);
         initial_scale = Math.min(initial_scale, 1);

         var translate_x = ((w - width*initial_scale) / 2);
         var translate_y = ((h - height*initial_scale) / 2);

         // Setup event listeners for model nodes.
         root.selectAll("polygon").each(function() {
              if (this.hasAttribute("fill")) {
                  // All model nodes should show the corresponding HDL, or the
                  // corresponding DOT graph when clicked.  dsdk::A_MODEL_NODEs
                  // are magenta, dsdk::A_SCHEDULED_MODEL_NODEs are white, and
                  // are not a direct descendant of the "graph" (the background
                  // is also white, but is a direct descendant of the "graph".
                  if (this.getAttribute("fill") == "magenta" ||
                      (this.getAttribute("fill") == "white" && !this.parentNode.classList.contains("graph"))) {
                      var g = this.parentNode;
                      var title = g.getElementsByTagName("title")[0].innerHTML;
                      g.addEventListener("click", function(){
                            // Ctrl+Click opens source, plain click opens graph.
                            if (window.event.ctrlKey) {
                              // TODO Eventually the filename will probably need
                              // to include a kernel/component subdirectory.
                              var filename = title.replace(/^\d+_/, "")+".vhd";
                              addHdlFileToEditor("lib/hdl/" + filename);
                              if (sideCollapsed) {
                                collapseAceEditor();
                                refreshAreaVisibility();
                                adjustToWindowEvent();
                              }
                            } else {
                              var new_hash = window.location.hash + "/" + title;
                              VIEWS.DOT.hash = new_hash;
                              goToDot(new_hash);
                            }
                        });
                  }
              }
         });

         // Clickdown for edge highlighting.
         root.selectAll("g.edge path")
           .on('click', function () {
               // TODO use parent
               if (dot_clickdown == this) {
                 dot_clickdown = null;
               } else {
                 dot_clickdown = this;
               }
               });

         // Edge/arrowhead highlighting.
         var highlightColor = "#1d99c1";
         root.selectAll("g.edge path")
           .on('mouseover', function () {
               $(this).attr({"stroke-width":5, "stroke":highlightColor});
               $(this).siblings("polygon").attr({"fill":highlightColor, "stroke":highlightColor, "stroke-width":3});
               })
           .on('mouseout', function () {
               if (dot_clickdown == this) return;
               $(this).attr({"stroke-width":1, "stroke":"black"});
               $(this).siblings("polygon").attr({"fill":"black", "stroke":"black", "stroke-width":1});
               });
         root.selectAll("g.edge polygon")
           .on('mouseover', function () {
               $(this).siblings("path").attr({"stroke-width":5, "stroke":highlightColor});
               $(this).attr({"fill":highlightColor, "stroke":highlightColor, "stroke-width":3});
               })
           .on('mouseout', function () {
               if (dot_clickdown == this) return;
               $(this).siblings("path").attr({"stroke-width":1, "stroke":"black"});
               $(this).attr({"fill":"black", "stroke":"black", "stroke-width":1});
               });


         // TODO use translateExtent() to prevent translating out of frame?
                      //.translateExtent([10 - X, 10 - Y, 2 * X - 10, 2 * Y - 10])
                      //.translateExtent([[0, 0], [2 * Y - 10]])

         var scaled_x = initial_scale * X;
         var scaled_y = initial_scale * Y;
         scaled_x += translate_x;
         scaled_y += translate_y;
         var zoom = d3.behavior.zoom()
                      .scaleExtent([0, 1.5])
                      .scale(initial_scale)
                      .translate([scaled_x, scaled_y])
                      .on("zoom", zoomed);
         d.select("g").attr("transform","translate(" + scaled_x + "," + scaled_y +")scale(" + initial_scale + "," + initial_scale + ")");
         d.call(zoom);
         if (!$('#dot_edges_toggle').is(':checked')) {
           $("#svg_container").find("g.edge").toggle();
         }
     });
    updateDotHierarchy();
}

function zoomed() {
    var graph = d3.select("#svg_container svg g");
    graph.attr("transform", "translate(" + d3.event.translate + ")scale(" + d3.event.scale + ")");
}

function
adjustToWindowEvent()
{
    setReportPaneHeight();
    stickTableHeader();
    if (!sideCollapsed) adjustEditorButtons();
    var svg = $("#svg_container svg");
    if(svg.length > 0) {
      svg[0].style.width = $("#svg_container").width();
      svg[0].style.height = $("#svg_container").height();
    }
}

function resizeEditor()
{
    if (sideCollapsed) return;

    var editor;
    for (var i = 0; i < fileJSON.length; i++) {
        if (fileJSON[i].name == curFile || fileJSON[i].path == curFile) {
            editor = fileJSON[i].editor;
            break;
        }
    }
    if (editor) editor.resize();
}

function refreshAreaVisibility() {
    $(currentPane + " #area-table-content tr").each(function() {
        if ($(this).attr('data-level') == "0" && $(this).is(":hidden")) {
            $(this).toggle();
        }
    });
}

function updateURLHash() {
    if (history.pushState) {
        history.pushState(null, null, view.hash);
    } else {
        location.hash(view.hash);
    }
}

function goToView(viewId, update) {
    var newView = VIEWS[viewId];
    if (!newView) { updateURLHash(); return; }
    if (view != newView) {
        $(currentPane).toggle();
        view = newView;
        currentPane = "#report-pane-view" + view.value;
        $(currentPane).toggle();
        if (view.clickDown !== null && view.clickDown.getAttribute('index')) {
            changeDivContent(view.clickDown.getAttribute('index'));
        } else {
            changeDivContent(0);
        }
        if (view == VIEWS.DOT && isValidDot) {
            // Collapse editor and details to maximize screen space for the graph
            if (!sideCollapsed) collapseAceEditor();
            if (!detailCollapsed) collapseDetails();
        }
    }
    if (update) {
        updateURLHash();
    }
    if (view == VIEWS.SPV) {
        if (!spv_graph && isValidSystemViewer) {
            // Allow browser to update the display
            $('#SPG').html(GRAPH_LOADING_DIV);
            setTimeout(function() {
                  spv_graph = new StartGraph(mavJSON, "SPV");
                  refreshAreaVisibility();
                  adjustToWindowEvent();
              }, 20);
        }
        else if (isValidSystemViewer) spv_graph.refreshGraph();
        else $('#SPG').html("&nbspSystem viewer data is invalid!");
    }
    else if (view == VIEWS.LMEM) {
        if (!lmem_graph && isValidMemoryViewer) {
            var hasLMem = addLMemTree();
            if (hasLMem) {
                $('#LMEMG').html("<br>&nbspClick on a memory variable to render it!");
            } else {
                $('#LMEMG').html("&nbspThere is no " + ((flow == FLOWS.OPENCL) ? "kernel" : "component") + " memory variable in the design file!");
            }
        }
        else if (isValidMemoryViewer) lmem_graph.refreshGraph();
        else $('#LMEMG').html("&nbsp " + view.name + " data is invalid!");
    }
    else if (view == VIEWS.CSPV) {
        if (!cspv_graph && isValidSystemViewer) {
            var hasComp = addComponentTree();
            if (hasComp) {
                $('#CSPG').html("<br>&nbspClick on a component to render it!");
            } else {
                $('#CSPG').html("&nbspThere is no " + ((flow == FLOWS.OPENCL) ? "kernel" : "component") + " in the design file!");
            }
        }
        else if (isValidSystemViewer) cspv_graph.refreshGraph();
        else $('#CSPG').html("&nbsp " + view.name + " data is invalid!");
    } else if (view == VIEWS.DOT) {
        var hash_split = window.location.hash.split("/");
        putSvg(hash_split[hash_split.length - 1]);
    }
    refreshAreaVisibility();
    adjustToWindowEvent();
}

function addReportColumn(reportEnum) {
    var report = REPORT_PANE_HTML;

    if (reportEnum == VIEWS.OPT) {
        report += LOOP_ANALYSIS_NAME;
        report += "</div><div class='panel-body' id='report-body' onscroll='adjustToWindowEvent()'>";
        report += "<table class='table table-hover' id='area-table-content'></table>";
    } else if (reportEnum == VIEWS.AREA_SYS || reportEnum == VIEWS.AREA_SRC) {
        report += "<table style='width:100%'><tr><td class='panel-heading-text'>";
        report += reportEnum.name + "<br>(area utilization values are estimated)<br>Notation <i>file:X</i> > <i>file:Y</i> indicates a function call on line X was inlined using code on line Y.";
        if (isValidAreaReport && !areaJSON.debug_enabled) {
            report += "<br><strong>Recompile without <tt>-g0</tt> for detailed area breakdown by source line.</strong>";
        }
        report += "</td><td>";
        report += "<span style='float:right'>";
        report += "<button id='collapseAll' type='button' class='text-left exp-col-btn'><span class='glyphicon glyphicon-chevron-up'></span>&nbsp;Collapse All&nbsp;</button>";
        report += "<button id='expandAll' type='button' class='text-left exp-col-btn'><span class='glyphicon glyphicon-chevron-down'></span>&nbsp;Expand All&nbsp;</button>";
        report += "</span>";
        report += "</td></tr></table>";

        report += "</div><div class='panel-body' id='report-body' onscroll='adjustToWindowEvent()'>";
        report += "<table class='table table-hover' id='area-table-content'></table>";
    } else if (reportEnum == VIEWS.SPV) {
        report = "<div class=\"classWithPad\" id=\"spv\"><div class=\"panel panel-default\" id=\"report-panel-body\"><div class=\"panel-heading\">";
        report += reportEnum.name;
        report += "<span style='float:right'><div id=\"layers\"></div></span>";
        report += "</div><div id='SPG' class='panel-body fade in active'></div>";
    } else if (reportEnum == VIEWS.SUMMARY) {
        report += reportEnum.name + "</div><div class='panel-body' id='report-body' onscroll='adjustToWindowEvent()'>";
        report += "<div id='area-table-content'></div>";
    } else if (reportEnum == VIEWS.VERIF) {
        report += reportEnum.name + "</div><div class='panel-body' id='report-body' onscroll='adjustToWindowEvent()'>";
        report += "<table class='table table-hover' id='area-table-content'></table>";
    } else if (reportEnum == VIEWS.LMEM) {
        report = "<div id=\"tree-list\" class=\"col col-sm-3\" id=\"report-pane-col1\">";
        report += "<div class=\"panel panel-default\" id=\"report-panel-tree\">";
        report += "<div class=\"panel-heading\">Memory list</div>";
        report += "<div id=\"tree-body\" class='panel-body'><div id=\"lmem-tree\"></div></div>";
        report += "</div></div>";

        report += "<div class=\"col col-sm-9\" id=\"report-pane-col2\">";
        report += "<div class=\"classWithPad\" id=\"lmem\"><div class=\"panel panel-default\" id=\"report-panel-body\"><div class=\"panel-heading\">";
        report += reportEnum.name;
        report += "<span style='float:right'><div id=\"layers-lmem\"></div></span>";
        report += "</div><div id='LMEMG' class='panel-body fade in active'></div>";
    } else if (reportEnum == VIEWS.CSPV) {
        report = "<div id=\"tree-list\" class=\"col col-sm-3\" id=\"report-pane-col1\">";
        report += "<div class=\"panel panel-default\" id=\"report-panel-tree\">";
        report += "<div class=\"panel-heading\">Component list</div>";
        report += "<div id=\"tree-body\" class='panel-body'><div id=\"comp-tree\"></div></div>";
        report += "</div></div>";

        report += "<div class=\"col col-sm-9\" id=\"report-pane-col2\">";
        report += "<div class=\"classWithPad\" id=\"comp\"><div class=\"panel panel-default\" id=\"report-panel-body\"><div class=\"panel-heading\">";
        report += reportEnum.name;
        report += "<span style='float:right'><div id=\"layers-comp\"></div></span>";
        report += "</div><div id='CSPG' class='panel-body fade in active'></div>";
    } else if (reportEnum == VIEWS.DOT) {
        report += "<table style='width:100%'><tr><td class='panel-heading-text'>";
        report += reportEnum.name;
        report += " &mdash; Use Ctrl + Left Click to open VHDL file for model nodes.";
        report += "</td><td>";

        // Controls
        report += "<span style='float:right'>";
        report += "<input  id='dot_edges_toggle'  type='checkbox' checked='checked'>Edges</input>";
        report += "<button id='dot_up_hierarchy'  type='button' >&nbsp;UP&nbsp;</button>";
        report += "<button id='dot_top_hierarchy' type='button' >&nbsp;TOP&nbsp;</button>";
        report += "</span>";
        report += "</td></tr></table>";

        report += "<span id='dot_hierarchy_text'>|module</span>";

        report += "</div><div class='panel-body' id='report-body' onscroll='adjustToWindowEvent()'>";
        report += "<div id='area-table-content' style='height:100%;'></div>";
    }

    report += "</div></div></div>";

    $("#report-pane-view" + reportEnum.value).html(report);
    $("#report-pane-view" + reportEnum.value + " #area-table-content").html(reportEnum.source);
}

function unsetClick() {
  if(view.clickDown !== null) {
    view.clickDown.classList.remove("nohover");
    view.clickDown.classList.remove("selected-item-highlight");
    view.clickDown = null;
    changeDivContent(0);
  }
}

// Go to the requested view when the URL hash is changed
$(window).on('hashchange', function() {
      var hash_view = window.location.hash.split("/")[0];
      goToView(viewHash[hash_view]);
    });

// navigation bar tree toggle
$(document).ready(function () {
    $('label.tree-toggle').click(function () {
        $(this).parent().children('ul.tree').toggle(200);
    });

    if (window.location.hash === "") {
        updateURLHash();
    } else {
      var hash_view = window.location.hash.split("/")[0];
      goToView(viewHash[hash_view]);
    }

    $(window).resize(function () {
        adjustToWindowEvent();
        resizeEditor();
    });

    function getChildren($row) {
        var children = [], level = $row.attr('data-level');
        var isExpanding;
        var maxExpandedLevel = Number(level) + 1;

        // Check if expanding or collapsing
        if ($row.next().is(":hidden")) {
            isExpanding = true;
        } else {
            isExpanding = false;
        }

        while($row.next().attr('data-level') > level) {
            // Always expand or collapse immediate child
            if($row.next().attr('data-level')-1 == level) {
                children.push($row.next());
                $row.next().attr('data-ar-vis',$row.next().attr('data-ar-vis')==1?0:1);
            } else {
                // expand if previously was expanded and parent has been expanded - maxExpandedLevel is used to tell if a child's immediate parent has been expanded
                if ($row.next().attr('data-ar-vis')==1 && isExpanding && $row.next().attr('data-level')<=(maxExpandedLevel+1)) {
                    children.push($row.next());
                    maxExpandedLevel = Math.max(maxExpandedLevel, $row.next().attr('data-level'));
                    // collapse if visible and element is some descendant of row which has been clicked
                } else if (!isExpanding && $row.next().is(":visible")) {
                    children.push($row.next());
                }
            }
            $row = $row.next();
        }
        return children;
    }


    // Expand or collapse when parent table row clicked
    $('#report-pane').on('click', '.parent', function() {
        var children = getChildren($(this));
        $.each(children, function () {
            $(this).toggle();
        });
        $(this).find('.ar-toggle').toggleClass('glyphicon-chevron-down glyphicon-chevron-right');
        stickTableHeader();
    });

    $('#report-pane').on('click', 'tr', function(d) {
        // do not change clicked state if we click an anchor (ie expand/collapse chevron)
        if (d.target.tagName.toLowerCase() === "a") return;
        // traverse up the DOMtree until we get to the table row
        for (d = d.target; d && d !== document; d = d.parentNode) {
            if (d.tagName.toLowerCase() === "tr") break;
        }
        // check to see if row is 'clickable'
        if (!$(this).attr('clickable')) return;
        if (view.clickDown == d) {
            // deselect row
            unsetClick();
        } else {
            // else select new row
            if (view.clickDown) {
                // deselect previous row
                unsetClick();
            }
            if ($(this).attr('index')) {
                // update "details" pane
                changeDivContent($(this).attr('index'));
            }
            view.clickDown = d;
            d.classList.add("nohover");
            d.classList.add("selected-item-highlight");
        }
    });

    // Display details on mouseover
    $('#report-pane').on('mouseover', 'tr', function() {
        if(view.clickDown === null && $(this).attr('index') && detailCollapsed === false) {
            changeDivContent($(this).attr('index'));
        }
    });

    $('.dropdown_nav').on('click', function () {
        // Clicking a .dropdown_nav item changes the page hash.
        // If the onHashChange event is supported in the browser, we will change views
        // using the corresponding event handler. Otherwise, do it explicitly here.
        if (!("onhashchange" in window)) {
            var viewId = $(this).attr("viewId");
            goToView(viewId);
        }
    });

    $('#collapse_source').on('click', collapseAceEditor);
    $('body').on('click', '#close-source', function () {
        collapseAceEditor();
        flashMenu();
    });

    $('#collapse_details').on('click', collapseDetails);
    $('body').on('click', '#close-details', function () {
        collapseDetails();
        flashMenu();
    });

    $('#report-pane').on('click', '#showFullyUnrolled', function() {
        $('.ful').each(function () {
            $(this).toggle();
        });
        stickTableHeader();
    });

    // Expand all the rows in area table
    $('#report-pane').on('click', '#expandAll', function () {
        // Get all the rows in the table which can expand/collapse
        var parents = $(currentPane + ' .parent');

        $.each(parents, function () {
            // Toggle all the children of that parent row
            var children = getChildren($(this));
            $.each(children, function () {
                // Set the data-ar-vis to be one so that it will expand afterwards
                $(this).attr('data-ar-vis', 1);
                // Only toggle if row is hidden and need to expand, or visible and need to collapse
                if ($(this).is(":hidden"))
                    $(this).toggle();
            });

            // Make all the arrow icons pointing down
            var iconsToToggle = $(this).find('.ar-toggle');
            $.each(iconsToToggle, function () {
                if ($(this).hasClass('glyphicon-chevron-right'))
                    $(this).toggleClass('glyphicon-chevron-down glyphicon-chevron-right');
            });
        });

        stickTableHeader();
    });

    // Collapse all the rows in area table
    $('#report-pane').on('click', '#collapseAll', function () {
        // Get all the rows in the table which can expand/collapse
        var parents = $(currentPane + ' .parent').toArray().reverse();

        $.each(parents, function () {
            // Toggle all the children of that parent row
            var children = getChildren($(this));
            $.each(children, function () {
                // Set the data-ar-vis to be zero so that the row states resets
                $(this).attr('data-ar-vis', 0);
                // Only toggle if row is hidden and need to expand, or visible and need to collapse
                if (!$(this).is(":hidden"))
                    $(this).toggle();
            });

            // Make all the arrow icons pointing down
            var iconsToToggle = $(this).find('.ar-toggle');
            $.each(iconsToToggle, function () {
                if ($(this).hasClass('glyphicon-chevron-down'))
                    $(this).toggleClass('glyphicon-chevron-down glyphicon-chevron-right');
            });
        });

        stickTableHeader();
    });

    // DOT viewer controls
    $('#report-pane').on('click', '#dot_up_hierarchy', function () {
        var hash = window.location.hash.split('/');
        hash.pop();
        if (hash.length > 1) goToDot(hash.join('/'));
    });

    $('#report-pane').on('click', '#dot_top_hierarchy', function () {
        goToDot("#dot/" + dot_top);
    });

    $('#report-pane').on('click', '#dot_edges_toggle', function (d) {
        if ($(this).is(':checked')) {
          $("#svg_container").find("g.edge").toggle();
        } else {
          $("#svg_container").find("g.edge").toggle();
        }
    });

});

function
flashMenu()
{
    var $menuElement = $('#collapse_sidebar');
    var interval = 500;
    $menuElement.fadeIn(interval, function () {
        $menuElement.css("color", "#80bfff");
        $menuElement.css("border", "1px solid #80bfff");
        $menuElement.fadeOut(interval, function () {
            $menuElement.fadeIn(interval, function () {
                $menuElement.fadeOut(interval, function () {
                    $menuElement.fadeIn(interval, function () {
                        $menuElement.css("color", "black");
                        $menuElement.css("border", "1px solid transparent");
                    });
                });
            });
        });
    });
}

function
collapseDetails()
{
    $('#detail-pane').toggle();
    detailCollapsed = !detailCollapsed;
    if (detailCollapsed) {
        // when details is collapsed, clear it
        changeDivContent(0);
    } else if (view.clickDown) {
        // when details is un-collapsed, update contents, if valid
        changeDivContent(view.clickDown.getAttribute('index'));
    }
    adjustToWindowEvent();
    resizeEditor();
}

function
collapseAceEditor()
{
    if (!isValidFileList) return;

    $('#editor-pane').toggle();
    if (sideCollapsed && isValidFileList) {
        $('#report-pane').css('width', '60%');
        sideCollapsed = false;
    } else {
        $('#report-pane').css('width', '100%');
        sideCollapsed = true;
    }
    adjustToWindowEvent();
    resizeEditor();
}

// Forces header of area report to remain at the top of the area table during scrolling
// (the header is the row with the column titles - ALUTs, FFs, etc.)
function
stickTableHeader()
{
    if (view !== VIEWS.AREA_SYS && view !== VIEWS.AREA_SRC && view !== VIEWS.OPT && view !== VIEWS.VERIF) return;

    var reportBody = $(currentPane + " #report-body")[0];
    if (!reportBody) return;
    var areaTable = $(currentPane + " #area-table-content")[0];
    if (!areaTable) return;
    var panel = reportBody.getBoundingClientRect();
    var table = areaTable.getBoundingClientRect();
    var rowWidth = 0.0;
    var tableWidth = table.width;
    var systemRow;

    var tableHeader = $(currentPane + ' #table-header').filter(function () {
        if ($(this).is(":visible")) return true;
        return false;
    });

    systemRow = $(currentPane + ' #first-row')
        .filter(function () {
            if ($(this).is(":visible")) return true;
            return false;
        });

    tableHeader.css("position", "absolute")
        .css("top", (panel.top - table.top))
        .css("left", 0);

    tableHeader.find('th').each(function (i) {
        var itemWidth = (systemRow.find('td').eq(i))[0].getBoundingClientRect().width;
        if (i === 0) {
            // This column contains the expand/collapse all button. Check if need to resize button
            if (itemWidth < $('#collapseAll').outerWidth() || itemWidth < 116) {
                $('#collapseAll').outerWidth(itemWidth);
                $('#expandAll').outerWidth(itemWidth);
            } else {
                $('#collapseAll').outerWidth(116);
                $('#expandAll').outerWidth(116);
            }
        }
        rowWidth += itemWidth;

        $(this).css('min-width', itemWidth);
    });

    // Set the Spacer row height equal to current tableHeader height
    systemRow.css("height", tableHeader.outerHeight());

    // if we just hid the selected row, unselect it and clear details pane
    if (view.clickDown && view.clickDown.offsetParent === null) {
        unsetClick();
    }
}

function
adjustEditorButtons()
{
    var editorWidth = $("#editor-pane").width();
    var editorExitButton = $("#close-source").outerWidth(true);
    $("#editor-nav-button").css("width", editorWidth - editorExitButton - 1);
}

function
setReportPaneHeight()
{
    var viewPortHeight = $(window).height() - 1;
    var navBarHeight = $(".navbar-collapse").height();
    var detailHeight = (detailCollapsed) ? 16 : $("#detail-pane").height();
    $('#report-pane, #editor-pane').css('height', viewPortHeight - navBarHeight - detailHeight);

    var panelHeight = $("#report-pane").height();
    var panelHeadingHeight = $(currentPane + ' .panel-heading').outerHeight();
    $(currentPane + ' #report-body').css('height', panelHeight - panelHeadingHeight);
    $(currentPane).css('height', $('#report-pane').innerHeight());

    if (view == VIEWS.SPV) {
        $('#SPG').css('height', panelHeight - panelHeadingHeight);
        $('#spg').css('height', panelHeight - panelHeadingHeight);
        $('#spg').css('width', $('#report-pane').innerWidth());
    }

    if (view == VIEWS.LMEM) {
        $('#LMEMG').css('height', panelHeight - panelHeadingHeight);
        $('#lmemg').css('height', panelHeight - panelHeadingHeight);
        $('#lmemg').css('width', $('#report-pane').innerWidth());
        $('ul.fancytree-container').css('height', panelHeight - panelHeadingHeight);
    }

    if (view == VIEWS.CSPV) {
        $('#CSPG').css('height', panelHeight - panelHeadingHeight);
        $('#cspg').css('height', panelHeight - panelHeadingHeight);
        $('#cspg').css('width', $('#report-pane').innerWidth());
        $('ul.fancytree-container').css('height', panelHeight - panelHeadingHeight);
    }

    var editorHeadingHeight = $('.input-group-btn').outerHeight();
    $('.tab-pane').css('height', panelHeight - editorHeadingHeight);

}

function
changeDivContent(idx, details)
{
    if (view == VIEWS.SPV || view == VIEWS.LMEM || view == VIEWS.CSPV) {
        if (!details) return;
        document.getElementById("details").innerHTML = "<ul class='details-list'>" + details + "</ul>";
    } else {
        document.getElementById("details").innerHTML = "<ul class='details-list'>" + detailValues[idx] + "</ul>";
    }
}

function
syncEditorPaneToLine( line, filename )
{
    var node;
    var editor;
    var index = 0;

    if (line == -1 || !isValidFileList) return;
    curFile = filename;

    index = fileIndexMap[filename];
    editor = (fileJSON[index]) ? fileJSON[index].editor : undefined;

    warn( editor, "Editor invalid!" );
    warn( line > 0, "Editor line number invalid!" );

    if (!editor || line < 1) return;

    var target = "li:eq(" + index + ")";
    $("#editor-pane-nav li").removeClass("active");
    $( "#editor-pane-nav " + target + " a" ).tab( "show" );
    $('.selected').html($("#editor-pane-nav " + target + " a").text());
    $('.mouseoverbuttontext').html($("#editor-pane-nav " + target + " p").text());
    editor.focus();
    editor.resize(true);
    editor.scrollToLine( line, true, true, function() {} );
    editor.gotoLine( line );
}

function syncEditorPaneToLineNoPropagagte(event, line, filename) {
    event.stopPropagation();
    syncEditorPaneToLine(line, filename);
}

function getShortFilename(path) {
    if (!isValidFileList) return path;
    for (var i = 0; i < fileJSON.length; i++)
        if (path.indexOf(fileJSON[i].name) != -1) return fileJSON[i].name;
    return path;
}

function getFilename(path) {
    if (!isValidFileList) return path;

    var name = path;
    for (var i = 0; i < fileJSON.length; i++) {
        if (path.indexOf(fileJSON[i].path) != -1) {
            return fileJSON[i].path;
        } else if (path.indexOf(fileJSON[i].name)) {
            name = fileJSON[i].name;
        }
    }
    return name;
}

function
warn(condition, message) {
    if (!condition) {
        console.log("WARNING: " + (message || ("Assertion Failed.")));
    }
}

function addLMemTree() {
    // Generate the Javascript datastructure for the local memory
    var memList = [];
    var lmemList = []; // Stores list of local memories

    // If there are local memories to render, then add it to the fancytree:
    if (lmvJSON.nodes.length !== 0) {
        // Iterate through the mavJSON
        lmvJSON.nodes.forEach(function (element) {
            // Check whether it's either a kernel (OpenCL) or component (HLS)
            if (element.type == "kernel" || element.type == "component") {
                var kernelName = element.name;
                var kernelEntry = { title: kernelName, isLmem: false, expanded: true, icon: "lib/fancytree/skin-win8/kernelicon.png", children: [] };
                // Find the local memory block
                element.children.forEach(function (node) {
                    if (node.type == "memtype" && node.name == "Local Memory") {
                        // Add all the local memories
                        node.children.forEach(function (lmemNode) {
                            var memEntry = { title: lmemNode.name, kernel: kernelName, isLmem: true, expanded: true, icon: "lib/fancytree/skin-win8/memicon.png", children: [] };
                            lmemNode.children.forEach(function (bankNode) {
                                var bankName = "<input id='" + kernelName + "_" + lmemNode.name + "_" + bankNode.name +
                                    "'  type='checkbox' checked='checked' name='" + bankNode.name + "' data-kernel='" + kernelName + "' data-lmem='" + lmemNode.name +
                                    "' value='' onClick='startGraphForBank(this)'>" + bankNode.name;
                                var bankEntry = { title: bankName, bank: bankNode.name, lmem: lmemNode.name, kernel: kernelName, isLmem: false, isBank: true, expanded: true, icon: false };
                                memEntry.children.push(bankEntry);
                            });
                            kernelEntry.children.push(memEntry);
                        });
                    }
                });
                memList.push(kernelEntry);
            }
        });

        // If there are local memories to render, then add it to the fancytree:

        $("#lmem-tree").fancytree({
            checkbox: false,
            source: memList,
            icon: true, // Disable the default icons
            clickFolderMode: 3, // 1:activate, 2:expand, 3:activate and expand, 4:activate (dblclick expands)
            activate: function (event, data) {
                // Check if a local memory is selected (do nothing for kernel)
                if (data.node.data.isLmem || data.node.data.isBank) {
                    var lmem_name, kernel_name, bank_name;
                    if (data.node.data.isLmem) {
                        lmem_name = data.node.title;
                    } else {
                        lmem_name = data.node.data.lmem;
                        bank_name = data.node.data.bank;
                    }
                    // Pass the name of the local memory into the rendering
                    kernel_name = data.node.data.kernel;

                    // Get the list of banks for that node that's selected
                    var bankElements = document.querySelectorAll('[id^="' + kernel_name + '_' + lmem_name + '"]');
                    var bankList = [];

                    // TODO: Find a way to add the checked:true filter within the query instead of doing a for loop
                    // Avoid using forEach on bankElements here because IE/Edge does not support it.
                    for (var i=0; i < bankElements.length; i++) {
                        if (bankElements[i].checked === true) bankList.push(bankElements[i].name);
                    }

                    // Start a new graph
                    if (isValidMemoryViewer) {
                        $('#LMEMG').html(GRAPH_LOADING_DIV);
                        setTimeout(function() {
                                lmem_graph = new StartGraph(lmvJSON, "LMEM", kernel_name, lmem_name, bankList, bank_name);
                                lmem_graph.refreshGraph();
                            }, 20);
                    }
                }
            }
        });

        return true;
    } else {
        return false;
    }
}

function startGraphForBank(element) {
    var kernelName = element.getAttribute("data-kernel");
    var lmemName = element.getAttribute("data-lmem");
    var bankName = element.getAttribute("name");

    var bankElements = document.querySelectorAll('[id^="' + kernelName + '_' + lmemName + '"]');
    var bankList = [];

    bankElements.forEach(function (elem) {
        if (elem.checked === true) bankList.push(elem.name);
    });

    if (isValidMemoryViewer) {
        $('#LMEMG').html(GRAPH_LOADING_DIV);
        setTimeout(function() {
                lmem_graph = new StartGraph(lmvJSON, "LMEM", kernelName, lmemName, bankList, bankName);
                lmem_graph.refreshGraph();
            }, 20);
    }

}

function addComponentTree() {
    // Generate the Javascript data structure for the components
    var compList = []; // List of components

    // If there are components to render, then add it to the fancytree:
    if (mavJSON.nodes.length !== 0) {
        // Iterate through the mavJSON
        mavJSON.nodes.forEach(function (element) {
            if (element.type == "kernel" || element.type == "component") {
                var compName = element.name;
                var compEntry = { title: compName, icon: "lib/fancytree/skin-win8/kernelicon.png"};
                compList.push(compEntry);
            }
        });

        // If there are local memories to render, then add it to the fancytree:

        $("#comp-tree").fancytree({
            checkbox: false,
            source: compList,
            icon: true, // Disable the default icons
            clickFolderMode: 3, // 1:activate, 2:expand, 3:activate and expand, 4:activate (dblclick expands)
            activate: function (event, data) {
                var comp_name = data.node.title;

                // Pass the name of the component into the rendering
                if (isValidSystemViewer) {
                    $('#CSPG').html(GRAPH_LOADING_DIV);
                    setTimeout(function() {
                          cspv_graph = new StartGraph(mavJSON, "CSPV", comp_name);
                          cspv_graph.refreshGraph();
                      }, 20);
                }
            }

        });

        return true;
    } else {
        return false;
    }
}
