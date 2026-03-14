//===----------------------------- table.js -------------------------------===//
//
// Parses JSON files and returns html tables as strings.
//
//===----------------------------------------------------------------------===//
"use strict";

// disable JSHint warning: Use the function form of "use strict".
// This warning is meant to prevent problems when concatenating scripts that
// aren't strict, but we shouldn't have any of those anyway.
/* jshint -W097 */

// remove invalid views from the VIEWS object
// views are invalid if the JSON is missing or invalid
function removeInvalidViews() {
    Object.keys(VIEWS).forEach(function(v) {
        var sel_view = VIEWS[v];
        if (sel_view.flow != FLOWS.BOTH && sel_view.flow != flow) {
            delete VIEWS[v];
        } else {
            // add clickDown and source fields
            sel_view.clickDown = null;
            sel_view.source = null;

            // Prepend 'Kernel' or 'Component' for memory viewer (view 7)
            if (VIEWS[v].value == VIEWS.LMEM.value) {
                sel_view.name = ((flow == FLOWS.OPENCL) ? "Kernel" : "Component") + " memory viewer";
            }
        }
    });
}

// try to parse the JSON
// return parsed JSON if valid
// return null if the JSON is empty or invalid
function tryParseJSON(json) {
    var valid = !$.isEmptyObject(json);
    if (valid) {
        if (typeof json !== "string") {
            // If we've gotten to this point, this is already a valid Javascript object.
            return json;
        }
        try {
            return JSON.parse(json);
        } catch(e) {
            console.log(e);
            return null;
        }
    } else {
        return null;
    }
}

// parseTable function is the core parser and should be run for each table
// jsonView:    table report view
// json:        JSON data
// initLevel:   initial level for first element in JSON data (determines indenting)
// getClass:    function to get the class of the table row
//              if no classes specific to table, pass returnEmptyString here
// needToParse: function to determine whether the parser should parse child
//              if parser should always parse children, pass returnTrue here
// needToSort:  function to determine whether the child needs sorting
//              if parser should never sort children, pass returnFalse here
// processData: function to read and modify data
//              if parser does not need to process data, pass doNothing here
function parseTable(jsonView, json, initLevel, getClass, needToParse, needToSort, processData) {

    var INDENT = 21;
    // When json does not have columns, it means the name is used as a message
    // details could be more a comprehensive message.
    var columns = (json.hasOwnProperty("columns")) ? json.columns : undefined;
    return createTable(initLevel);

    // create inner text for JSON table 
    function createTable(level) {
        var table = createTableHeader();
        table += (jsonView !== VIEWS.SUMMARY) ? addSpacerRow() : "";
        
        // special case for area tables, parse partitions separately
        if (jsonView === VIEWS.AREA_SYS || jsonView === VIEWS.AREA_SRC) {
            json.children.forEach(function(childRow) {
                if (childRow.type === "partition") table += parse(childRow, level, null, false);
            });
        }
        
        // recursively parse rows of the table
        table += parse(json, level, null, false);
        table += "</tbody>";

        return table;

        // create the table header
        function createTableHeader() {
            if (columns === undefined) return "";
            var table_header = "";

            table_header += "<thead><tr class='res-heading-row' data-ar-vis=0 data-level=0 id='table-header'>";

            columns.forEach( function(col, i) {
                table_header += "<th class='";
                if (i) table_header += "res-val";
                else   table_header += "res-title";
                table_header += "'>" + col + "</th>";
            });
            table_header += "</tr></thead>";

            return table_header;
        }
        
        // add the spacer row if the sticky table header is being used
        // the spacer row is added to take up the space underneath the table header
        function addSpacerRow() {
            var spacer = "<tr data-level=0 id='first-row'>";
            columns.forEach( function(col) {
                spacer += "<td>" + col + "</td>";
            });
            spacer += "</tr>";
            return spacer;
        }

        // recursively parse row and its children, add this information to the html table
        function parse(row, level, parent, updateData, replace_name) {
            var isParent       = row.hasOwnProperty('children') && row.children.length;
            var htmlClass      = getClass(row, isParent);
            var shortDetails   = getShortDetailsFromJSON(row.details);
            var ttDetails      = getToolTipDetailsFromJSON(row.details); // TODO: add tooltips to JSON, and use this to add tooltip to row/cell in table
            var divDetails     = (columns !== undefined) ? getHTMLDetailsFromJSON(row.details, row.name) : getHTMLDetailsFromJSON(row.details, undefined);  //  Details will not print the name when no column defined.
            var fileLine       = getFirstFileAndLine(row.debug);
            var htmlOut        = "";
            var htmlTemp       = "";
            var updateNextData = (!row.hasOwnProperty('data') || row.data === undefined || !row.data.length);
            var shorten_name   = true;

            row.data     = (updateNextData) ? [] : row.data; 
            row.count    = (row.hasOwnProperty('count') && row.count > 1) ? row.count : 0;
            row.level    = level;
            row.maxRes   = json.max_resources;

            // get filename and line for row
            // if no filename and line, check parent for valid filename and line
            row.filename = (fileLine !== undefined) ? fileLine.file : ((parent && parent.filename !== undefined) ? parent.filename : undefined);
            row.line     = (fileLine !== undefined) ? fileLine.line : ((parent && parent.line !== undefined) ? parent.line : undefined);

            // Add children
            if (isParent) {
                var sortedResourceChildren = [];
                var sortedOtherChildren = [];

                row.children.forEach(function(childRow) {
                    // Do not access partitions from kernel system, they should be parsed separately
                    if (needToParse(childRow)) {
                        htmlTemp = parse(childRow, level+1, row, updateNextData, row.name == "Feedback");
                        // This colours all of the resources with children except for split memory in red
                        // Split memory is determined using the detail string added at the bottom of the addLocalMemResources function in ACLAreaUtils.cpp
                        if (childRow.type == "resource" && (row.type == "module" || row.type == "function") && (childRow.hasOwnProperty('children') && childRow.children.length) && !(childRow.hasOwnProperty('details') && childRow.details.length && childRow.details[0].hasOwnProperty('text') && childRow.details[0].text.indexOf("was split into multiple parts due to optimizations") != -1)){
                            htmlTemp = htmlTemp.replace("res-row", "resource-totalres-row");
                        }
                        if (childRow.name == "Global interconnect" || childRow.name == "Data control overhead" || childRow.name == "Function overhead"){
                            htmlOut += htmlTemp;
                        // Split memory should be sorted at the top with all of the resources that don't have children
                        // Whether the memory is split or not is determined using the detail string added at the bottom of the addLocalMemResources function in ACLAreaUtils.cpp
                        } else if ((childRow.type == "resource" && !(childRow.hasOwnProperty('children') && childRow.children.length)) || (childRow.hasOwnProperty('details') && childRow.details.length && childRow.details[0].hasOwnProperty('text') && childRow.details[0].text.indexOf("was split into multiple parts due to optimizations") != -1)){
                            sortedResourceChildren.push({ name: childRow.name, html: htmlTemp });
                        } else {
                            sortedOtherChildren.push({ name: childRow.name, html: htmlTemp });
                        }
                    }
                });

                // If items need to parse, sort before pushing into html
                // Sort and push resources without children first, followed by everything else sorted
                if (jsonView !== VIEWS.SUMMARY) sortedResourceChildren.sort(nameSort);
                sortedResourceChildren.forEach( function(sChild) {
                    htmlOut += sChild.html;
                });
                if (jsonView !== VIEWS.SUMMARY) sortedOtherChildren.sort(nameSort);
                sortedOtherChildren.forEach( function(sChild) {
                    htmlOut += sChild.html;
                });
            }

            if (isParent || replace_name) {
                // TODO: perhaps build a more general solution wherein any debug
                // loc in the row title becomes a link - e.g. private variables, etc.
                if ((replace_name || (row.hasOwnProperty('replace_name') && row.replace_name)) &&
                    row.hasOwnProperty('debug') && row.debug.length && row.debug[0].length &&
                    row.debug[0][0].line !== 0) {
                  var t = "";
                  var count = 0;
                  row.debug[0].forEach( function(d) { 
                      if (count++ > 0) {
                        t += " > ";
                        if (count & 1) t += "\n";
                      }
                      t += "<a style='cursor:pointer;' onClick='syncEditorPaneToLineNoPropagagte(event, " + d.line;
                      t += ", \"" + getFilename(d.filename) + "\")'";
                      t += ">" + getShortFilename(d.filename) + ":" + d.line + "</a>";
                      });
                  row.name = t;
                  shorten_name = false;
                }
            }

            // do report specific data processing
            processData(row, parent, updateData);

            // Add details to detail pane
            if (divDetails !== "") {
                detailValues.push(divDetails);
                ++detailIndex;
            }

            // Add to serialized html
            return tableRow(row.name, htmlClass, isParent, row.level, row.filename, row.line, row.data, shortDetails, divDetails, shorten_name) + htmlOut;
        }

        // Create html table row from information
        function tableRow(name, htmlClass, isParent, level, filename, line, data, shortDetails, divDetails, shorten_name) {
            if (level < 0) return "";

            // add class, data level, and detail index
            var row = "<tr class='" +  htmlClass + "' data-ar-vis=0 clickable='1' data-level=" + level +
                      " index=" + ((divDetails.length) ? detailIndex : 0);

            // add linking to soure editor
            if (line !== undefined && filename !== undefined && filename !== "") row += " onClick='syncEditorPaneToLine(" + line + ", \"" + filename + "\")'" ;
            row += ">";

            // remove any possible file path in the name (data gets too long)
            var short_title = name;
            if (shorten_name) short_title = name.match(/.*\/.*:\d/i) ? name.replace(/.*\//g, '') : name;

            // add indent to row in table
            row += "<td class='res-title' style='padding-left:" + ((level) ? level*INDENT : 8) + "px;'>";

            // add chevron to collapsible parents
            if (htmlClass.indexOf('parent') !== -1) row += "<a class='ar-toggle glyphicon glyphicon-chevron-right' style='color:black;padding-left:2px;'></a>&nbsp";
            else                                    row += "&nbsp&nbsp";

            // add row name, data, and details
            row += short_title + "</td>";
            for (var i = 0; i < data.length; i++) {
                row += "<td class='res-val'>" + data[i] + "</td>";
            }
            if (columns && columns.last_item() === "Details") row += "<td class='res-val'>" + shortDetails + "</td>";

            row += "</tr>";
            return row;
        }

        // Get file and line number of first debug info
        function getFirstFileAndLine(debugValue) {
            if (debugValue === undefined || !debugValue.length || !debugValue[0].length) {
                return undefined;
            }
            return {file: debugValue[0][0].filename, line: debugValue[0][0].line};
        }

        // Sort names of kernels and basic blocks
        // Eg. Order should be Block1, ..., Block9, Block10 instead of Block1, Block10, ... Block9
        function nameSort(data1, data2) {
            var isUpper1 = (data1.name[0] && data1.name[0] == data1.name[0].toUpperCase());
            var isUpper2 = (data2.name[0] && data2.name[0] == data2.name[0].toUpperCase());

            //  undefined, {numeric: true, sensitivity: 'case'}
            if      ( isUpper1 && !isUpper2) return -1;
            else if ( isUpper2 && !isUpper1) return 1;
            else return data1.name.localeCompare(data2.name, 'en-US-u-kn-true');
        }

        
    }
}

// if brief detail is specified, return brief detail and remove brief detail from
// details array
// if no brief detail is specified, return truncated version of details from 
// details section. these details are shown in the area table, since no brief detail is
// explicitly added
function getShortDetailsFromJSON(JSON_details) {
    if (!JSON_details || !JSON_details.length) return "";
    var short_details = "";

    // check for brief details and return brief detail if found
    JSON_details.forEach(function(detail, i) {
        if (detail.type == "brief") {
            short_details = detail.text;
            JSON_details.splice(i, 1);
        }
    });
    if(short_details !== "") return short_details;

    // create brief details from table type
    if (JSON_details[0].type === "table") {
        var detail_count = 3;
        var keys = Object.keys(JSON_details[0]);
        for (var i = 0; i < keys.length && i < detail_count; ++i) {
            if (keys[i] === "type") {
                detail_count++;
                continue;
            }
            var tbl_detail = keys[i] + JSON_details[0][keys[i]];
            short_details += "<li>" + tbl_detail.substring(0, 10) + "..." + "</li>";
        }

    // create brief details from text
    } else {
        // Limit the number of details which appear to 3
        for (var j = 0; j < JSON_details.length && j < 3; ++j) {
            var text_detail = JSON_details[j].text;
            if (text_detail) {
              short_details += "<li>" + text_detail.substring(0, 10) + "..." + "</li>";
            }
        }
    }

    return short_details;
}


// TODO: finish adding tooltip details
// return tool tip detail
// if no tool tip exists, return null
function getToolTipDetailsFromJSON(JSON_details) {
    if (!JSON_details || !JSON_details.length) return null;
    var tt = null;
    JSON_details.forEach(function(detail, i) {
        if (detail.type == "tooltip") {
            tt = detail.text;
            JSON_details.splice(i, 1);
        }
    });
    return tt;
}

// Generate html details from JSON
function getHTMLDetailsFromJSON(JSON_details, title) {
    if (!JSON_details || !JSON_details.length) return "";

    var DETAIL = {
        TEXT:    "text",
        BRIEF:   "brief",
        TABLE:   "table",
        UNKNOWN: "unknown"  // for temporary use when tracking bullet points,
                            // none of the JSON details should have this type
    };

    var html_details = (title !== undefined) ? "<b>" + title + ":</b><br>" : "";
    var list_stack = [];
    list_stack.push(DETAIL.UNKNOWN);
    return generateHTMLDetails(html_details, JSON_details, list_stack);

    // Generate html details from array (list) or object (table)
    function generateHTMLDetails(html_details, JSON_details, list_stack) {

        JSON_details.forEach(function (detail) {
            var use_html_list = implementHTMLList(JSON_details, list_stack);

            // add <ul> and </ul> tags for details which are implemented in list style
            if (detail.type == DETAIL.TEXT && (list_stack.last_item() == DETAIL.UNKNOWN ||
                list_stack.last_item() == DETAIL.TABLE) && use_html_list) {
                html_details += "<ul style='margin-left: 10px; padding-left: 10px;'>";
            } else if (detail.type === DETAIL.TABLE && list_stack.last_item() === DETAIL.TABLE &&
                      use_html_list) {
                html_details += "</ul>";
            }

            // keep track of type of details being printed
            list_stack[list_stack.length-1] = detail.type;

            // generate <li> or <table> html detail
            html_details = generateSingleHTMLDetail(html_details, detail, list_stack, use_html_list);
        });

        // close last list if necessary
        if (list_stack.last_item() == DETAIL.TEXT && implementHTMLList(JSON_details, list_stack)) {
            html_details += "</ul>";
        }

        list_stack.pop();
        return html_details;
    }

    // Generate html table data or list item for detail
    function generateSingleHTMLDetail(html_details, JSON_details, list_stack, use_li) {

        // if detail is type table:
        // print key in first column, value in second column
        if (JSON_details.type == "table") {
            // these variables are needed to sort the table details in a more resonable order;
            // Required size and Implemented size come one after the other, bank information stays together, Additional info comes at the end
            var req_and_impl_size = [];
            var banks_related = [];
            var additional_info_html = "";
            var other_details = [];
            var reference_link = "";
            var html_temp;

            html_details += "<table id='DetailsTable' class='table-striped'>";
            $.each(JSON_details, function (key, value) {
                if (key === "type") return;
                html_details += "<tr>";
                html_details += "<td>" + key + "</td>";
                if (value instanceof Array) {
                list_stack.push(DETAIL.UNKNOWN);
                html_details += "<td>";
                html_details = generateHTMLDetails(html_details, value, list_stack);
                html_details += "</td>";
                } else {
                html_temp += "<td>" + value + "</td>";
                }

                // group the detail into the appropriate group depending on the key
                if (key.indexOf("Additional information") != -1){
                    additional_info_html = html_temp;
                } else if (key.indexOf("Requested size") != -1) {
                    req_and_impl_size.unshift(html_temp);
                } else if (key.indexOf("Implemented size") != -1) {
                    req_and_impl_size.push(html_temp);
                } else if (key.toLowerCase().indexOf("bank") != -1) {
                    banks_related.push(html_temp);
                } else if (key.toLowerCase().indexOf("reference") != -1) {
                    reference_link = html_temp;
                } else {
                    other_details.push(html_temp);
                }
            });
            // add the details to the actual html_details string in the appropriate order
            req_and_impl_size.forEach( function(html_string) {
                html_details += html_string;
            });
            other_details.forEach( function(html_string) {
                html_details += html_string;
            });
            banks_related.forEach( function(html_string) {
                html_details += html_string;
            });
            html_details += additional_info_html;
            html_details += reference_link;

            html_details += "</table>";

        // otherwise add text detail
        // add as <li> unless only single item
        } else {
            if (use_li) html_details += "<li>";
            html_details += insertLinks(JSON_details.text, JSON_details.links);
            if (JSON_details.details) {
                list_stack.push(DETAIL.UNKNOWN);
                html_details = generateHTMLDetails(html_details, JSON_details.details, list_stack);
            }
            if (use_li) html_details += "</li>";
        }
        return html_details;
    }                                                   

    // Given the text and links, replace the instances of '%L' with the proper link information
    // Guide: add <a></a> link to OpenCL Best Practices Guide
    // View:  add <a></a> link to switch views (to Area analysis, Loops report, etc.)
    // File:  add <a></a> link to file and source line in editor
    function insertLinks(text, links) {
        if (links === undefined) return text;
        links.forEach(function (link) {
        var link_name = "";

        // insert link to Best Practices Guide
        if (link.guide) {
            link_name = "<a href='" + link.link + "'>" + link.guide + "</a>";

        // insert link to alternate view
        } else if (link.view) {
            var jsonView = VIEWS.SUMMARY;
            Object.keys(VIEWS).forEach(function (v) {
                if (VIEWS[v].name === link.view) jsonView = VIEWS[v];
            });
            link_name = "<a href='" + jsonView.hash + "' onClick='goToView(" + jsonView.value + ", true)'>" + jsonView.name + "</a>";

        // insert link to file and line
        } else if (link.filename == "Unknown location") {
            link_name = "Unknown location";
        } else {
            link_name = "<a href='#' onClick='syncEditorPaneToLine(" + link.line + ", \"" +
                        getFilename(link.filename) + "\")'>" + link.filename.substring(link.filename.lastIndexOf('/') + 1) + ": " + link.line + "</a>";
        }
        text = text.replace(/\%L/, link_name);
        });
        return text;
    }

    // Return true if details should be implemented in an html list
    function implementHTMLList(details, list_stack) {
        // print the details in a point form list if:
        //   1. there are multiple details                   or
        //   2. the detail has subdetails                    or
        //   3. the details is a subdetail of a text detail
        //   Note: it is assumed that the detail is of type 'text'
        return details.length > 1 ||
            (details.length == 1 && details.hasOwnProperty('details') && details.details.length) ||
            (list_stack.length > 1 && list_stack[list_stack.length - 2] == DETAIL.TEXT);
    }
}

// parses summary data and returns html tables 
function parseSummaryData(infoJSON, warningsJSON, json, quartusJSON) {
    var summaryInfo = "";

    // TODO: switch to common parser, once infoJSON is updated
    summaryInfo += myParseTable(infoJSON);

    if (quartusJSON !== undefined) {
        summaryInfo += "<table class='table table-hover'>";
        summaryInfo += "<text><b>&nbsp;" + quartusJSON.quartusFitClockSummary.name + "</b></text>";
        summaryInfo += parseTable(VIEWS.SUMMARY, quartusJSON.quartusFitClockSummary, -1, getClass, returnTrue, returnFalse, doNothing);
        summaryInfo += "</table>";
        // check quartusFitResourceSummary before parsing
        if (quartusJSON.hasOwnProperty('quartusFitResourceUsageSummary')) {
            summaryInfo += "<table class='table table-hover'>";
            summaryInfo += "<text><b>&nbsp;" + quartusJSON.quartusFitResourceUsageSummary.name + "</b></text>";
            summaryInfo += parseTable(VIEWS.SUMMARY, quartusJSON.quartusFitResourceUsageSummary, -1, getClass, returnTrue, returnFalse, doNothing);
            summaryInfo += "</table>";
        }
    }

    // create table for Kernel Summary
    if (json.hasOwnProperty('performanceSummary')) {
        summaryInfo += "<table class='table table-hover'>";
        summaryInfo += "<text><b>&nbsp;" + json.performanceSummary.name + "</b></text>";
        summaryInfo += parseTable(VIEWS.SUMMARY, json.performanceSummary, -1, getClass, returnTrue, returnFalse, doNothing);
        summaryInfo += "</table>";
    }

    // create table for Estimated Resource Usage
    if (json.hasOwnProperty('estimatedResources')) {
        summaryInfo += "<table class='table table-hover'>";
        summaryInfo += "<text><b>&nbsp;" + json.estimatedResources.name + "</b></text>";
        summaryInfo += parseTable(VIEWS.SUMMARY, json.estimatedResources, -1, getClass, returnTrue, returnFalse, processData);
        summaryInfo += "</table>";
    }

    // create table for Compile Warnings
    if (json.hasOwnProperty('compileWarnings')) {

        // temporarily put warnings.json into compileWarnings
        // TODO: convert this to perl.
        //   - may end up needing to distinguish between warnings based on origin (clang, opt, or llc)
        //     in which case this may stay as javascript, or an extra field will need to be added to the JSON
        //       Eg. , "origin": "clang"
        warningsJSON.rows.forEach(function(r) {
            try {
                if (r.details && r.details.length) {
                    var warnDetails = [];
                    r.details.forEach(function(detail) {
                        warnDetails.push({type: "text", text: detail});
                    });
                    r.details = warnDetails;
                }
                json.compileWarnings.children.push(r);
            } catch(e) {
                console.log(e);
            }
        });
        if (json.compileWarnings.children.length < 1) {
            json.compileWarnings.children.push({"name":"None"});
        }

        summaryInfo += "<table class='table table-hover'>";
        summaryInfo += "<text><b>&nbsp;" + json.compileWarnings.name + "</b></text>";
        summaryInfo += parseTable(VIEWS.SUMMARY, json.compileWarnings, -1, getClass, returnTrue, returnFalse, doNothing);
        summaryInfo += "</table>";
    }

    return summaryInfo;

    // for summary table, the necessary classes are added to the JSON file
    function getClass(row, parent) {
        var classes = "";
        if (row.hasOwnProperty("classes")) {
            row.classes.forEach(function(c) {
                classes += " " + c;
            });
        }
        return classes;
    }

    // add correct percentages to Estimated Resource Usage data
    function processData(row, parent) {
        if (row.hasOwnProperty("data_percent")) {
            row.data.forEach(function(data, i) {
                if (row.data_percent.length > i) {
                    row.data[i] += " (" + row.data_percent[i].toFixed(0) + "%)";
                }
            });
        }
    }
}

// parses loop data and returns html table
function parseLoopData(json) {
    
    return parseTable(VIEWS.OPT, json, -1, getClass, returnTrue, returnFalse, processData);

    function getClass(row, parent) {
        return "res-row" + ((row.name === "Fully unrolled loop") ? " ful" : "");
    }

    function processData(row, parent) {
        row.name += " (";
        if (row.line > 0) { row.name += row.filename.substring(row.filename.lastIndexOf('/') + 1) + ":" + row.line; }
        else if (row.line === 0) { row.name += row.filename.substring(row.filename.lastIndexOf('/') + 1); }
        else { row.name += "Unknown location"; }
        row.name  += ")";
    }
}

// parses area data and returns html table
function parseAreaData(json) {

    return parseTable(VIEWS.AREA_SYS, json, 0, getClass, needToParse, needToSort, processData);

    function getClass(row, parent) {
        return ((row.type === "resource") ? "res-row collapse" : (row.type + "-totalres-row collapse")) + ((parent) ? " parent" : "");
    }

    function needToParse(row) {
        return (row.type !== "partition");
    }

    function needToSort(childType, parentType, childHasChildren) {
        return ((childType == "resource" && parentType !== "function") || childType == "basicblock" || childType == "function" || (childType == "resource" && parentType === "function" && childHasChildren));
    }

    function processData(row, parent, updateData) {
        // add count for instructions
        row.name += ((row.count && row.name !== "State") ? (" (x" + row.count + ")") : "");

        // if row does not have data, do not print it
        // this only happens in cases where a parent row has no children and no data
        if (!row.data.length) {
            row.level = -1;
            return;
        }

        // round ALUTs and FFs to nearest number
        // round RAMs and DSPs to first decimal
        row.data[0] = Math.round(row.data[0]);
        row.data[1] = Math.round(row.data[1]);
        row.data[2] = Number(row.data[2].toFixed(1));
        row.data[3] = Number(row.data[3].toFixed(1)); 

        // sum area data of parent
        if (parent !== null && parent !== undefined && updateData) {
            row.data.forEach(function(d, i) {
                if (parent.data.length > i) parent.data[i] += d;
                else                        parent.data.push(d);
            });
        }

        // add percentages to resource data
        if (row.maxRes !== null && row.maxRes !== undefined && (row.type !== "resource" || (row.hasOwnProperty('children') && row.children.length && (parent !== null && parent !== undefined && (parent.type == "function" || parent.type == "module"))))) {
            for (var j = 0; j < row.data.length; j++) {
                row.data[j] = row.data[j] + " (" + Math.round(row.data[j] / row.maxRes[j] * 100) + "%)";
            }
        }
    }
}


function parseVerifData(json) {

    // TODO: use common parser (below) instead of parseLoopTable once verification JSON is updated
    /*return parseTable(VIEWS.VERIF, json, 0, getClass, returnTrue, returnFalse, doNothing);

    function getClass(row, parent) {
        return "res-row";
    }*/

    return parseLoopTable(json, false);
}


// TODO: finish adding Dynamic II Est parser
// the following is a loose estimate of what the Dynamic II Est parser will look like based on a mock up version
// when a component tree is created, parseIIEstData will need to be called for each component
// assuming iiestJSON has an array of JSON data for each kernel, or iiestJSON maps names of kernels to data
function parseIIEstData(json) {
    
    var iiEstInfo = "";

    // json.compIIEstTable.columns is expected to be
    // ["Min est component II", "Max est component II", "Min est component latency", "Max est component latency", "Details"]
    if (json.hasOwnProperty('compIIEstTable')) {
        iiEstInfo += "<table class='table table-hover'>";
        // TODO: replace json.compIIEstTable.name with actual name "Kernel: <kernel name>"
        //       and update button with correct onclick utility
        iiEstInfo += "<text><b>&nbsp;" + json.compIIEstTable.name + "<br><button onclick='calculateButton()'>Calculate</button></b></text>";
        iiEstInfo += parseTable(VIEWS.II, json.compIIEstTable, -1, getClass, returnTrue, returnFalse, processDataForCompII); 
        iiEstInfo += "</table>";
    }

    // json.loopIIEstTable.columns is expected to be 
    // ["", "Pipelined", "II", "Serialize Region", "Single trip count latency", "Min trip count", , "Max trip count", "Min est II", "Max est II", "Details"]
    if (json.hasOwnProperty('loopIIEstTable')) {
        iiEstInfo += "<table class='table table-hover'>";
        iiEstInfo += parseTable(VIEWS.II, json.loopIIEstTable, -1, getClass, returnTrue, returnFalse, processDataForLoopII);
        iiEstInfo += "</table>";
    }

    return iiEstInfo;

    // assuming class is always res-row
    function getClass(row, parent) {
        return "res-row";
    }

    function processDataForCompII(row, parent) {
        // replace ? with input fields
        row.data.forEach(function(d, i) {
            if (d === "?") row.data[i] = "<input type=\"text\">"; // may want to include a default value or disabled tag in JSON? or hard code which columns are disabled
        });

        // since comp II table has no name column, shift first data into name
        row.name = row.data.shift();
    }

    function processDataForLoopII(row, parent) {
        // replace ? with input fields
        row.data.forEach(function(d, i) {
            if (d === "?") row.data[i] = "<input type=\"text\">"; // may want to include a default value or disabled tag in JSON? or hard code which columns are disabled
        });

    }
}
//-------------------------------------------------------------------------------------------

// Temporary function for parsing info.json
// TODO: once these JSON files are modified to fit the JSON schema in perl,
//       remove this and use common parser
//-------------------------------------------------------------------------------------------
function myParseTable(o) {
    var t = "<table class='table table-hover'>";
    var precision = 0;
    var hasDetailsCol = false;

    // title
    if (o.hasOwnProperty('name')) {
        t += "<text><b>&nbsp;" + o.name + "</b></text>";
    }

    // get precision for floats
    if (o.hasOwnProperty('precision')) {
        precision = o.precision;
    }

    if (o.hasOwnProperty("sticky_title")) {
    }

    // table header
    if (o.hasOwnProperty("columns")) {
        // details column?
        if (o.columns.indexOf("Details") > -1) {
            hasDetailsCol = true;
        }
        if (o.hasOwnProperty("sticky_title")) {
            t += "<thead><tr class='res-heading-row' data-ar-vis=0 data-level=0 id='table-header'>";
        } else {
            t += "<tbody><tr class=\"nohover\" index=0>";
        }
        o.columns.forEach( function(col) {
            if (o.hasOwnProperty("sticky_title")) {
                t += "<th>" + col + "</th>";
            } else {
                t += "<td><b>" + col + "</b></td>";
            }
        });
        t += "</tr>";
        if (o.hasOwnProperty("sticky_title")) {
            t += "</thead><tbody>";
            // create spacer row
            t += "<tr data-level=0 id=first-row>";
            o.columns.forEach(function (h) {
                t += "<td>" + h + "</td>";
            });
            t += "</tr>";
        }
    }

    // table rows
    if (o.hasOwnProperty('children')) {
        o.children.forEach(function(row) {
            t += myAddRow(row, 0);
        });
    // TEMPORARY: remove when infoJSON and warningsJSON is commonized
    } else if (o.hasOwnProperty('rows')) {
        o.rows.forEach(function(row) {
            t += myAddRow(row, 0);
        });
    }

    t += "</tbody></table>";
    return t;

    //// functions

    function myAddRow(row, level) {
        var indent = 12;
        var r = "";
        // start row
        r += "<tr";

        // Add special classes
        var row_clickable = true;
        if (row.hasOwnProperty("classes")) {
            r += " class=\"";
            row.classes.forEach(function(c) {
                r += " " + c;
                if (c == "summary-highlight") {
                    row_clickable = false;
                }
            });
            r += "\"";
        }

        // deal with details
        if (row.hasOwnProperty("details")) {
            r += myParseDetails(row);
        } else {
            r += " index=0";
            if (row_clickable) {
                r += " clickable='1'";
            }
        }

        // deal with debug info
        if (row.hasOwnProperty('debug') && row.debug[0][0].line !== 0) {
            r += " onClick='syncEditorPaneToLine(" + row.debug[0][0].line;
            r += ", \"" + getFilename(row.debug[0][0].filename) + "\")'";
        }

        // end row start
        r += ">";

        // Add row title if it exists
        if (row.hasOwnProperty("name")) {
            r += "<td style='text-indent:" + level*indent + "px'>";
            r += row.name + "</td>";
        }

        // Add row data
        if (row.data) {
            row.data.forEach(function(data, i) {
                if (isFloat(data)) {
                    var p;
                    if (precision instanceof Array) {
                        p = precision[i];
                    } else {
                        p = precision;
                    }
                    data = data.toFixed(p);
                }
                if (row.hasOwnProperty("data_percent")) {
                if (row.data_percent.length > i) {
                    data += " (" + row.data_percent[i].toFixed(0) + "%)";
                }
                }
                r += "<td>" + data + "</td>";
            });
        }

        // add details column?
        if (hasDetailsCol) {
            if (row.hasOwnProperty("details")) {
            r += "<td>" + row.details[0] + "</td>";
            } else {
            r += "<td></td>";
            }
        }

        // end row
        r += "</tr>";

        // add sub-rows if they exist
        if (row.hasOwnProperty("subrows")) {
            row.subrows.forEach(function(sr) {
                r += myAddRow(sr, level + 1);
            });
        }

        return r;
    } // myParseTable::myAddRow()

    function myParseDetails(row) {
        var r = "";

        if (row.details.length) {

            // Remove when warnings.json is converted to new detail information
            var detail = "<b>" + row.name + ":</b><br>";
            row.details.forEach( function(d) { detail += d; });
            detailValues.push(detail);
            r += " index=\"" + (++detailIndex) + "\"";
        } else {
            r += " index=0";
        }
        r += " clickable=\"1\"";

        return r;
    } // myParseTable::myParseDetails()

    // myParseTable::isFloat()
    function isFloat(n) {
        return Number(n) === n && n % 1 !== 0;
    }

    // myParseTable::isInt()
    function isInt(n) {
        return Number(n) === n && n % 1 === 0;
    }
}
//-------------------------------------------------------------------------------------------


// Temporary function for parsing verification data
// TODO: once verification data is updated to same schema as loops, remove this and 
//       use common parser
//-------------------------------------------------------------------------------------------
/// main::parseLoopTable
function
parseLoopTable(theJSON, parseLoops) {
    var loop = theJSON;
    var indent = 12;
    var htmlOut = "";

    if (loop.functions.length === 0) {
        return "<i>&nbspDesign has no loops</i>";
    }

    var first = true;

    htmlOut = createTableHeader();

    loop.functions.forEach( function(d) {
        htmlOut += addResource(d);
    });

    htmlOut += "</tbody>";
    return htmlOut;

    /// parseLoopTable::createTableHeader
    function
    createTableHeader() {
        var table_header = "";

        table_header += "<thead><tr class='res-heading-row' data-ar-vis=0 data-level=0 id='table-header'><th class='res-title'></th>";
        theJSON.columns.forEach(function (h) {
            table_header += "<th class='res-val'>" + h + "</th>";
        });
        table_header += "<th class='res-val'>Details</th></tr></thead>";

        // Spacer row with fake data
        table_header += "<tbody><tr data-level=0 id=first-row><td>Spacer</td>";
        theJSON.columns.forEach(function (h) {
            table_header += "<td>" + h + "</td>";
        });
        table_header += "<td>Details</td></tr>";  // use two Details words as default spacing

        return (table_header);
    }

    /// parseLoopTable::createRow
    function
    createRow(title, data, details, line, level, filename, resources)
    {
        var row = "<tr class='res-row ";
        var hasDetails = true;
        if (details === undefined || details.length === 0) {
            hasDetails = false;
        }

        // Custom class to show/hide Fully unrolled loops
        if (title == "Fully unrolled loop") { row += " ful"; }

        row += "'";

        // Assign optIndex to 0 if no details or to a value
        if (hasDetails) {
            detailIndex += 1;
            row += " index=" + detailIndex + " clickable=1";
        }
        else { row += " index=0 clickable=1"; }

        if (line > 0) { row += " onClick='syncEditorPaneToLine(" + line + ", \"" + filename + "\")'"; }


        row += "><td class='res-title' style='text-indent:" + level*indent + "px'>";
        row += title;
        if (parseLoops) {
            row += " (";
            if (line > 0) { row += filename.substring(filename.lastIndexOf('/') + 1) + ":" + line; }
            else if (line === 0) { row += filename.substring(filename.lastIndexOf('/') + 1); }
            else { row += "Unknown location"; }
            row  += ")";
        }
        row  += "</td>";

        // add data columns
        for (var j = 0; j < data.length; j++) {
            row += "<td class='res-val'>" + data[j] + "</td>";
        }

        // add details column
        if (hasDetails) { row += "<td class='res-val' >" + details[0] + "</td>"; }
        else { row += "<td class='res-val'></td>"; }

        // details section
        if (resources !== undefined && resources.length > 0) {
            var infohtml = "<ul class='details-list'><b>" + title + ":</b><br>";
            for (var ri = 0; ri < resources.length; ri++) {
                if (resources[ri].name !== undefined) infohtml += resources[ri].name + "<br>";
                if (resources[ri].subinfos === undefined) {
                    continue;
                }
                infohtml += "<ul>";
                var subinfos = resources[ri].subinfos;
                for (var i = 0; i < subinfos.length; i++) {
                    if (subinfos[i].info.debug !== undefined && subinfos[i].info.debug.length > 0 && subinfos[i].info.debug[0].length > 0) {
                        var infoFilename = getFilename(subinfos[i].info.debug[0][0].filename);
                        var short_infoFilename = infoFilename.substring(infoFilename.lastIndexOf('/') + 1); //only use the file name, no directories
                        var infoLine = subinfos[i].info.debug[0][0].line;
                        //var infoNodeId = subinfos[i].info.debug[0][0].nodeId;  //Feature in 17.0 Add node ID to debug info
                        infohtml += "<li>" + subinfos[i].info.name + " (";
                        infohtml += "<a style='cursor:pointer;color:#0000EE' onClick='syncEditorPaneToLine(" + infoLine + ",\"" + infoFilename + "\")'>" + short_infoFilename + ":" + infoLine + "</a>";

                        // there can be multiple debug location, i.e. LSU merge
                        for (var di = 1; di < subinfos[i].info.debug[0].length; di++) {
                            infoLine = subinfos[i].info.debug[0][di].line;
                            if (infoFilename != getFilename(subinfos[i].info.debug[0][di].filename)) {
                                infoFilename = getFilename(subinfos[i].info.debug[0][di].filename);
                                infohtml += ", <p style='cursor:pointer;color:#0000EE' onClick='syncEditorPaneToLine(" + infoLine + ",\"" + infoFilename + "\")'>" + short_infoFilename + ":" + infoLine + "</p>";
                            }
                            else {
                                infohtml += ", <a style='cursor:pointer;color:#0000EE' onClick='syncEditorPaneToLine(" + infoLine + ",\"" + infoFilename + "\")'>" + infoLine + "</a>";
                            }
                        }
                        infohtml += ")";
                    } else {
                        infohtml += "<li>" + subinfos[i].info.name + " (Unknown location)";
                    }
                    infohtml += "</li>";
                }
                infohtml += "</ul>";
            }
            infohtml += "</ul>";
            detailValues.push(infohtml);
        }
        else {
            if (hasDetails) {
                detailValues.push("<ul class='details-list'><b>" + title + ":</b><br>" + details[0] + "</ul>");
            }
        }
        row += "</tr>";
        return (row);
    }

    /// parseLoopTable::addResource
    function
    addResource(r)
    {
        var line = -1;
        var filename = "";
        var details = "";
        var level = 1;  // loop level starts at level 1. Level 0 is for kernel

        if (r.hasOwnProperty('debug') && r.debug.length > 0 && r.debug[0].length > 0) {
            line = r.debug[0][0].line;
            if (line > 0) { filename = getFilename(r.debug[0][0].filename); }
            else { filename = r.debug[0][0].filename; }
            level = r.debug[0][0].level;
        }

        return createRow(r.name, r.data, r.details, line, level, filename, r.resources);
    }

}
//-------------------------------------------------------------------------------------------

function returnFalse() { return false; }
function returnTrue()  { return true; }
function returnEmptyString()  { return ""; }
function doNothing()   {}

///// Array Prototype Utility functions

// Added to simplify accessing last item in array
// Given var arr = [1,2,3]
//       arr.last_item()       <- returns 3
if (!Array.prototype.last_item) {
    Array.prototype.last_item = function () {
        return this[this.length - 1];
    };
}

