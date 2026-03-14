
function StartGraph(mavData, graphType, kernelName, lmemName, bankList, bankName) {
    "use strict";

    // Node and link data from the JSON file
    var allNodes = mavData.nodes,
        allLinks = mavData.links;

    var flattenedNodes = {},    // all nodes included in graph
        flattenedLinks = {},    // all links included in graph
        nodeMap        = {},    // all nodes from JSON file (including duplicate LSUs)
        linkMap        = {},    // all links to nodes
        invisNodes     = [],    // nodes which disappear from layer deselected (eg. control, memory)
        invisLinks     = [],    // links which disappear when layer deselected
        subsetNodes    = [];    // all filtered nodes for the graph


    var clickDown;              // node which was last clicked

    var nodeTypes = [];

    var chanWidth        = 5,
        nodeHeight       = 5,
        nodeWidth        = 20,
        portRadius       = 2,
        containerPadding = 15;

    var memsysNodes = [];
    var lmemNode;
    var lmemBankNode;

    var spg, spgSVG, spgGroup;

    var panelWidth, panelHeight, graphWidth, graphHeight;
    var zoomFitScale;
    var zoom;
    var marginOffset = 10;

    var seenGlobal = false; // For determining if this component stores to a global variable

    // A dictionary of node detail keys that should be hidden
    var hiddenDetails = { "type": true,
                          "Component": true,
                          "Fmax Bottlenecks": true,
                          "Pipelined": true,
                          "Subloops":true,
                          "Loops To":true }; 

    // Add all 3 graphs
    addGraph(graphType);

    // Create maps of nodes and links
    createNodeMap("", allNodes);
    createLinkMap(allLinks);

    // Preprocess the nodes if it's LMEM graphType
    if (graphType == "LMEM") {
        subsetNodes = preProcessNodes(bankList);
    }

    // Preprocess the nodes if it's CSPV graphType
    else if (graphType == "CSPV") {
        subsetNodes = preProcessCompNodes(kernelName);
    }

    // Collapse similar channels
    preProcessChannels();

    // Create separation container
    spg.setNode("container", {});

    // Create nodes and links
    if (graphType == "LMEM") {
        createNodes("", subsetNodes, graphType, kernelName, lmemName, bankList);
    } else if (graphType == "SPV") {
        createNodes("", allNodes, graphType);
    } else if (graphType == "CSPV") {
        createNodes("", subsetNodes, "CSPV", kernelName);
    }
    createLinks(allLinks, graphType);

    // Create the renderer
    var spgRenderer = new dagreD3.render();

    // Render the graph
    if (graphType == "SPV") {
        spgRenderer(d3.select("#spg g"), spg);
    } else if (graphType == "LMEM") {
        spgRenderer(d3.select("#lmemg g"), spg);
    } else if (graphType == "CSPV") {
        spgRenderer(d3.select("#cspg g"), spg);
    }

    // Setup the stall point graph
    setupSPG(graphType);

    // FUNCTIONS
    // --------------------------------------------------------------------------------------------

    // Print nodes and links to console
    function printNodesAndLinks() {

        console.log("NODES");
        Object.keys(flattenedNodes).forEach(function (key) {
            console.log(key);
        });

        console.log("LINKS");
        Object.keys(flattenedLinks).forEach(function (key) {
            console.log(key, flattenedLinks[key]);
        });
    }

    function getUniqueNodeName(id) {
      return "_"+id;
    }

    function getNodeID(n) {
      return getUniqueNodeName(n.id);
    }

    function getNode(id) {
      if (!flattenedNodes[id]) return flattenedNodes[getUniqueNodeName(id)];
      return flattenedNodes[id];
    }

    function isStallable(id) {
        var node = flattenedNodes[id];
        if (!node) return false;
        var details = getDetails(node);
        return (details && details['Stall-free'] && details['Stall-free'] === "No");
    }

    // Create graphs for tabs
    function addGraph(graphType) {

        // Remove graph_loading div
        d3.selectAll("#graph_loading").remove();

        // Add graph canvas
        if (graphType == "SPV") {
            d3.select("#SPG")
            .append("svg")
            .attr("id", "spg")
            .attr("width", 2000);

            // Create the input graph
            spg = new dagreD3.graphlib.Graph({ compound: true })
              .setGraph({ nodesep: 25, ranksep: 35, edgesep: 15, rankdir: "TB"})   // nodesep: horizontal distance between nodes
                                                                                   // ranksep: vertical distance between nodes
                                                                                   // edgesep: padding between container and nodes
                                                                                   // rankdir: direction of the graph
                                                                                   // acyclicer: choose algorithm for correcting cycles in dagre-d3 (fix case: 409063)
              .setDefaultEdgeLabel(function () { return {}; });

            // Create svg group
            spgSVG = d3.select("#spg");
            spgGroup = spgSVG.append("g")
                .attr('class', 'graph');
        }
        else if (graphType == "CSPV") {
            d3.select("#CSPG")
            .append("svg")
            .attr("id", "cspg")
            .attr("width", 2000);

            // Create the input graph
            spg = new dagreD3.graphlib.Graph({ compound: true })
              .setGraph({ nodesep: 25, ranksep: 35, edgesep: 15, rankdir: "TB", acyclicer: "greedy" })   // nodesep: horizontal distance between nodes
                                                                                    // ranksep: vertical distance between nodes
                                                                                    // edgesep: padding between container and nodes
                                                                                    // rankdir: direction of the graph
                                                                                    // acyclicer: choose algorithm for correcting cycles in dagre-d3 (fix case: 409063)
              .setDefaultEdgeLabel(function () { return {}; });

            // Create svg group
            spgSVG = d3.select("#cspg");
            spgGroup = spgSVG.append("g")
                .attr('class', 'graph');
        }
        else if (graphType == "LMEM") {
            d3.select("#LMEMG")
            .append("svg")
            .attr("id", "lmemg")
            .attr("width", 1000);

            // Create the input graph
            spg = new dagreD3.graphlib.Graph({ compound: true })
              .setGraph({ nodesep: 25, ranksep: 35, edgesep: 15, rankdir: "LR" })   // nodesep: horizontal distance between nodes
                                                                                    // ranksep: vertical distance between nodes
                                                                                    // edgesep: padding between container and nodes
                                                                                    // rankdir: Direction of the graph
              .setDefaultEdgeLabel(function () { return {}; });

            // Create svg group
            spgSVG = d3.select("#lmemg");
            spgGroup = spgSVG.append("g")
                .attr('class', 'graph');
        }


    }

    // Create map of all nodes: node id -> node data
    function createNodeMap(parent, nodes) {
        nodes.forEach(function (n) {
            nodeMap[getNodeID(n)] = n;
            n.parent = parent;
            if (n.type == "memsys") {
                memsysNodes.push(n);
                if (nodeMap[parent].name == "Global Memory") n.global = true;
            }
            if (n.children) createNodeMap(getNodeID(n), n.children);
        });
    }

    // Create map of all links: node id -> all links associated with node
    function createLinkMap(links) {
        links.forEach(function (lnk) {
            if (!linkMap[getUniqueNodeName(lnk.from)]) linkMap[getUniqueNodeName(lnk.from)] = [];
            linkMap[getUniqueNodeName(lnk.from)].push(lnk);

            if (!linkMap[getUniqueNodeName(lnk.to)]) linkMap[getUniqueNodeName(lnk.to)] = [];
            linkMap[getUniqueNodeName(lnk.to)].push(lnk);
        });
    }

    // Filter out the instruction nodes, etc. which are not part of the specified local memory
    function preProcessNodes(bankList) {
        var nodeList = [];

        // Given an edge which links to the arbitration, add the ones which have an instruction linked to it
        function preProcessArbLinks(arb_link) {
            var arbNodeLinkFrom = nodeMap[getUniqueNodeName(arb_link.from)];
            var arbNodeLinkTo = nodeMap[getUniqueNodeName(arb_link.to)];

            if (arbNodeLinkFrom.type == "inst" || arbNodeLinkFrom.type == "interface") {
                nodeList.push(arbNodeLinkFrom);
            } else if (arbNodeLinkTo.type == "inst" || arbNodeLinkTo.type == "interface") {
                nodeList.push(arbNodeLinkTo);
            }
        }

        // Start at the memsys nodes and then move outward
        memsysNodes.forEach(function (n) {
            // Get the kernel name of the particular memsys node by getting the parent of parent
            // memsys -> memtype -> kernel
            // node.parent returns id, then use nodeMap to convert id -> node
            var currKernel = nodeMap[nodeMap[n.parent].parent];

            if (n.name == lmemName && currKernel.name == kernelName) {
                // Found the correct local memory
                lmemNode = n;

                // Add to the nodeList
                nodeList.push(n);

                // Look for arbitration nodes
                if (n.children) {
                    //  Get the banks
                    var curBankList = n.children;
                    curBankList.forEach(function (b) {
                        // Check if this bank is supposed to be rendered
                        if (bankList.indexOf(b.name) != -1) {
                            // If the bank matches the bankName, then store this node
                            if (b.name == bankName) lmemBankNode = b;

                            var portList = b.children;
                            if (portList) {
                                portList.forEach(function (p) {
                                    // Check for neighbouring nodes to the port
                                    // A port only has one node connected to it: either an arbitration node or an instruction node
                                    linkMap[getUniqueNodeName(p.id)].forEach(function (link) {
                                        // If there is an arbitration node connected to this port and add it
                                        var nodeLinkFrom = nodeMap[getUniqueNodeName(link.from)];
                                        var nodeLinkTo = nodeMap[getUniqueNodeName(link.to)];
                                        if (nodeLinkFrom.type == "arb") {
                                            // Add arbitration node to nodeList
                                            nodeList.push(nodeLinkFrom);
                                            // Find all instruction neighbours of the arbitration node
                                            linkMap[getUniqueNodeName(nodeLinkFrom.id)].forEach(preProcessArbLinks);
                                        }
                                        else if (nodeLinkTo.type == "arb") {
                                            // Add arbitration node to nodeList
                                            nodeList.push(nodeLinkTo);
                                            // Find all instruction neighbours of the arbitration node
                                            linkMap[getUniqueNodeName(nodeLinkTo.id)].forEach(preProcessArbLinks);
                                        } else if (nodeLinkTo.type == "inst") {
                                            nodeList.push(nodeLinkTo);
                                        } else if (nodeLinkFrom.type == "inst") {
                                            nodeList.push(nodeLinkFrom);
                                        } else if (nodeLinkFrom.type == "interface") {
                                            nodeList.push(nodeLinkFrom);
                                        } else if (nodeLinkTo.type == "interface") {
                                            nodeList.push(nodeLinkTo);
                                        }
                                    });
                                });
                            }
                        }
                    });
                }
           }
        });

        return nodeList;

    }

     // Filter out the instruction nodes, etc. which are not part of the specified components
    function preProcessCompNodes(kernel_name) {
        var nodeList = [];

        mavData.nodes.forEach(function (n) {
            if (n.type == "component" && n.name == kernel_name) {
                nodeList.push(n);
            } else if (n.type == "stream") {
                // Check if the destination of the stream is in the desired component
                var lnk = linkMap[getNodeID(n)][0]; // Should only be one edge
                if (linkMap[getNodeID(n)].length !== 1) console.log("Error: stream node has more than one edge!");
                var destNodeID = nodeMap[getUniqueNodeName(lnk.from)].type == "stream" ? lnk.to : lnk.from;
                var destNode = nodeMap[getUniqueNodeName(destNodeID)];
                var destBBNode = nodeMap[destNode.parent];
                var destCompNode = nodeMap[destBBNode.parent];
                if (destCompNode.name == kernel_name) {
                    nodeList.push(n);
                }
            } else if (n.type == "memtype") {
                nodeList.push(n);
            } else if (n.type == "interface") {
                // Check if the interface node is for this particular component 
                if (getDetails(n) && getDetails(n).Component == kernel_name) {
                    nodeList.push(n);
                }
            }
        });

        return nodeList;
    }

    // Collapse similar channels
    function preProcessChannels() {
        var channels = [],
            rLink,
            wLink,
            read = {},
            write = {},
            found = false;

        Object.keys(nodeMap).forEach(function (key) {
            if (nodeMap[key].type == "stream" && (nodeMap[key].name == "do" || nodeMap[key].name == "return")) {
              nodeMap[key].visible = true;
              return;
            }
            if (nodeMap[key].type == "channel" || nodeMap[key].type == "stream") {
                read = {};
                write = {};
                rLink = {};
                wLink = {};
                var nodeID = getNodeID(nodeMap[key]);

                if (linkMap[nodeID].length < 2) {
                    nodeMap[key].visible = true;
                    return;
                }

                if (linkMap[nodeID][0].from == nodeMap[key].id) {
                    read = linkMap[nodeID][0].to;
                    rLink = linkMap[nodeID][0];
                    write  = linkMap[nodeID][1].from;
                    wLink = linkMap[nodeID][1];
                } else {
                    write  = linkMap[nodeID][0].from;
                    wLink = linkMap[nodeID][0];
                    read = linkMap[nodeID][1].to;
                    rLink = linkMap[nodeID][1];
                }

                nodeMap[key].read = read;
                nodeMap[key].write = write;
                nodeMap[key].count = 1;
                found = false;

                for (var i = 0; i < channels.length; i++) {
                    if (channels[i].name == nodeMap[key].name &&
                        verifyDetails(nodeMap[getUniqueNodeName(channels[i].read)], nodeMap[getUniqueNodeName(read)]) &&
                        verifyDetails(nodeMap[getUniqueNodeName(channels[i].write)], nodeMap[getUniqueNodeName(write)])) {
                        channels[i].count++;
                        nodeMap[key].visible = false;
                        rLink.from = channels[i].id;
                        wLink.to = channels[i].id;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    nodeMap[key].visible = true;
                    channels.push(nodeMap[key]);
                }
            }
        });
    }

    // Get abbreviated name for instructions
    function getLabelName(name) {
        if (name.indexOf("Load") != -1) return "LD";
        else if (name.indexOf("Store") != -1) return "ST";
        else if (name.indexOf("Read") != -1) return "RD";
        else if (name.indexOf("Write") != -1) return "WR";
        else return (name);
    }

    // Add highlighting persistence and syncing to editor and details pane
    function addClickFunctions(graph) {

        var nodes = graph.selectAll("g.node rect, g.nodes .label, g.node circle, g.node polygon")
            .on('click', function (d) {

                refreshPersistence(graph);
                if (clickDown == d) {
                    clickDown = null;
                } else {
                    highlightNodes(d, graph);
                    changeDivContent(0, getHTMLDetailsFromJSON(flattenedNodes[d].details, flattenedNodes[d].name));
                    clickDown = d;
                }

                // details and editor syncing (reset if no line number)
                if (getNode(d).hasOwnProperty('debug') && getNode(d).debug.length > 0 && getNode(d).debug[0].length > 0)
                  syncEditorPaneToLine(getNode(d).debug[0][0].line, getFilename(getNode(d).debug[0][0].filename));
                else
                  syncEditorPaneToLine(1, curFile);
            });

        var clusters = graph.selectAll("g.cluster rect")
            .on('click', function (d) {

                refreshPersistence(graph);
                if (clickDown == d) {
                    clickDown = null;
                } else if (flattenedNodes[d].type == "memsys" || flattenedNodes[d].type == "bank" || flattenedNodes[d].type == "bb" || flattenedNodes[d].type == "csr") {
                    highlightNodes(d, graph);
                    changeDivContent(0, getHTMLDetailsFromJSON(flattenedNodes[d].details, flattenedNodes[d].name));
                    clickDown = d;
                }

                // details and editor syncing (reset if no line number)
                if (getNode(d).hasOwnProperty('debug') && getNode(d).debug.length > 0 && getNode(d).debug[0].length > 0)
                  syncEditorPaneToLine(getNode(d).debug[0][0].line, getFilename(getNode(d).debug[0][0].filename));
                else
                  syncEditorPaneToLine(1, curFile);
            });
    }

    // Add highlighing to nodes and links
    function addHighlighting(graph) {

        var highlightColor = "#1d99c1";
        var highlightNodeColor = "#8ECCE0";

        var clusterHighlights = graph.selectAll("g.cluster rect")
            .on('mouseover', function (d) {
                if (getNode(d) && (flattenedNodes[d].type == "memsys" || flattenedNodes[d].type == "bank" || flattenedNodes[d].type == "bb" || flattenedNodes[d].type == "csr")) {
                    highlightNodes(d, graph);
                }
                if (!clickDown && flattenedNodes[d] && getDetails(flattenedNodes[d])) {
                    changeDivContent(0, getHTMLDetailsFromJSON(flattenedNodes[d].details, flattenedNodes[d].name));
                }
            })
            .on('mouseout', function (d) {
                if (clickDown != d) {
                    refreshPersistence(graph);
                    highlightNodes(clickDown, graph);
                }
            });

        var nodeHighlights = graph.selectAll("g.node rect, g.label, g.node circle, g.node polygon")
            .on('mouseover', function (d) {
                highlightNodes(d, graph);
                if (!clickDown && flattenedNodes[d] && getDetails(flattenedNodes[d])) {
                    changeDivContent(0, getHTMLDetailsFromJSON(flattenedNodes[d].details, flattenedNodes[d].name));
                }
            })
            .on('mouseout', function (d) {
                if (clickDown != d) {
                    refreshPersistence(graph);
                    highlightNodes(clickDown, graph);
                }

            });


        // Highlight link, associated nodes on mouseover
        var linkHighlights = graph.selectAll("g.edgePath path")
            .on('mouseover', function (d) {

                var connections = graph.selectAll("g.edgePath")
                    .filter(function (k) {
                        return d.v == k.v && d.w == k.w;
                    });

                connections.selectAll("path")
                    .style("opacity", 0.5)
                    .style("stroke-width", 5)
                    .style("stroke", highlightColor);

                var connectedNodes = graph.selectAll("g.node rect, g.node circle, g.node polygon")
                    .filter(function (n) {
                        return n == d.v || n == d.w;
                    })
                    .style("stroke-width", 3)
                    .style("stroke", highlightNodeColor);

                connections.selectAll("marker")
                    .attr({
                        "markerUnits": "userSpaceOnUse",
                        "preserveAspectRatio": "none",
                        "viewBox": "0 0 40 10",
                        "refX": 6,
                        "markerWidth": 40,
                        "markerHeight": 12
                    })
                    .style("stroke-width", 0);
                connections.selectAll("marker path")
                    .attr("style", "fill:" + highlightColor + "; opacity: 1; stroke-width:0");

            })
            .on('mouseout', function (d) {
                if (clickDown != d) refreshPersistence(graph);
                if (clickDown) highlightNodes(clickDown, graph);
            });
    }

    // Highlight associated links and nodes
    function highlightNodes(d, graph) {

        var highlightColor = "#1D99C1";
        var highlightNodeColor = "#8ECCE0";

        var associatedNodes = [];
        associatedNodes.push(d);

        // Find associated links and nodes
        var connections = graph.selectAll("g.edgePath").filter(function (k) {
            if (invisNodes.indexOf(k.v) != -1 || invisNodes.indexOf(k.w) != -1) return false;
            if (invisLinks.indexOf(k) != -1) return false;
                if (k.v == d || k.w == d) {
                    if (associatedNodes.indexOf(k.v) == -1) associatedNodes.push(k.v);
                    if (associatedNodes.indexOf(k.w) == -1) associatedNodes.push(k.w);
                    return true;
                }
            return false;
        });

        var numFirstNeighbours = associatedNodes.length;
        // Get additional links if graphType is LMEM if the hovered node is not an arbitration node
        // When hovering over an instr, then want to highlight the path to the port through arb (if any): inst -> arb -> port
        // When hovering over a port, then want to highlight the arb and ALL inst to that arb
        if (graphType == "LMEM" && d && typeof d != 'undefined' && !isNaN(d.replace("_","")) && flattenedNodes[d].type != "arb") {
            connections = graph.selectAll("g.edgePath").filter(function (k) {
                if (invisNodes.indexOf(k.v) != -1 || invisNodes.indexOf(k.w) != -1) return false;
                if (invisLinks.indexOf(k) != -1) return false;
                // Check 2 cases:
                // 1. If d is type instr, then check that tail (k.v) is in one of the 1st neighbours of d.
                // 2. If d is a type port, then check that head (k.w) is in one of the 1st neighbours of d. This essentially gets the inst->arb->port case
                var indexOfKV = associatedNodes.indexOf(k.v);
                var indexOfKW = associatedNodes.indexOf(k.w);
                // Only check the if the edge is connected to the 1st neighbours of d
                if ((indexOfKV != -1 && indexOfKV < numFirstNeighbours) && (flattenedNodes[d].type == "inst" || flattenedNodes[d].type == "interface") ||
                    (indexOfKW != -1 && indexOfKW < numFirstNeighbours && flattenedNodes[d].type == "port")) {
                    if (indexOfKV == -1) associatedNodes.push(k.v);
                    if (indexOfKW == -1) associatedNodes.push(k.w);
                    return true;
                }
                return false;
            });
        }

        // Highlight links
        connections.selectAll("path")
            .attr("style", "stroke:" + highlightColor + "; opacity: 0.5; fill:none; stroke-width:5;");

        // Highlight nodes
        var connectedNodes = graph.selectAll("g.cluster rect, g.node rect, g.node circle, g.node polygon, g.cluster rect")
            .filter(function (n) {
                if (associatedNodes.indexOf(n) == -1) return false;
                else if (getNode(n).type == "kernel" || getNode(n).type == "component" || getNode(n).type == "memtype") return false;
                else return true;
            })
            .style("stroke-width", 3)
            .style("stroke", highlightNodeColor);

        // Color and highlight arrowheads
        connections.selectAll("marker")
            .attr({
                "markerUnits": "userSpaceOnUse",
                "preserveAspectRatio": "none",
                "viewBox": "0 0 40 10",
                "refX": 6,
                "markerWidth": 40,
                "markerHeight": 12
            })
        .style("stroke-width", 0);
        connections.selectAll("marker path")
            .attr("style", "fill:" + highlightColor + "; opacity: 1; stroke-width:0");
    }

    // Add tooltips to display details
    function addToolTips(graph) {
        var tt = function (n) {
            var name = "";
            if (flattenedNodes[n].type == "channel" || flattenedNodes[n].type == "stream") name += flattenedNodes[n].type + " ";

            name += flattenedNodes[n].name;

            if (flattenedNodes[n].count && flattenedNodes[n].count > 1) name += " (x" + flattenedNodes[n].count + ")";

            var text = "<p class='name'>" + name + " Info</p><p class='description'>";
            var details = getDetails(flattenedNodes[n]);
            Object.keys(details).forEach(function (k) {
                if (typeof details[k] !== "string" && typeof details[k] !== "number") return;
                if (!(hiddenDetails[k]) && !(k.indexOf("Arguments from") != -1 && k.indexOf(kernelName) == -1)) {
                    text += k + ": " + details[k] + "<br>";
                }
            });
            text += "</p>";
            return text;
        };

        graph.selectAll("g.node rect, g.cluster rect, g.node circle, g.node polygon")
            .filter(function (d) {
                if (d.indexOf("container") != -1 || d == "glbmem") return false;
                return (flattenedNodes[d] && getDetails(flattenedNodes[d]));
            })
            .style("fill", "white")
            .attr("title", function (d) { return tt(d); })
            .each(function (v) { $(this).tooltip({ content: function() {return $(this).attr('title');}, tooltipClass: "custom_tooltip", position: {my: "left bottom", at: "center top-2"} }); }); 
    }

    // Return true if node is merge or branch
    function isMergeOrBranch(node) {
        return (flattenedNodes[node].name == "loop" || flattenedNodes[node].name == "begin" || flattenedNodes[node].name == "end" || flattenedNodes[node].name == "loop end");
    }

    this.refreshGraph = function () {
        if (clickDown) {
            changeDivContent(0, getHTMLDetailsFromJSON(getDetails(flattenedNodes[clickDown], flattenedNodes[clickDown].name)));
        }
    };

    // Refresh persistent highlighting
    function refreshPersistence(graph) {

        graph.selectAll("g.edgePath path")
            .style("opacity", 0.3)
            .style("stroke-width", 2)
            .style("stroke", "#333");

        graph.selectAll("g.cluster rect, g.node rect, g.node circle, g.node polygon")
            .filter(function(d) { return getNode(d); })
            .style("stroke-width", 1.5)
            .style("stroke", "#999");

        colorArrowheads(graph);
        if (graph == spgSVG)
            colorNodes(graph);
    }

    // Format arrowheads
    function colorArrowheads(graph) {
        var markers = graph.selectAll("marker")
            .attr({
                "markerUnits": "userSpaceOnUse",
                "preserveAspectRatio": "none",
                "viewBox": "0 0 40 10",
                "refX": 8,
                "markerWidth": 30,
                "markerHeight": 8
            })
            .style("stroke-width", 0);
        graph.selectAll("marker path")
            .attr("style", "fill:#333; opacity: 1; stroke-width:0");
    }

    // Color basic blocks with loops that cannot be unrolled
    function colorNodes(graph) {
        var loopBlockColor   = "#ff0000",
            singlePumpColor  = "#5cd6d6",
            doublePumpColor  = "#239090",
            glbmemColor      = "#006699",
            loopEdgeColor    = "#000099",
            mergeBranchColor = "#ff8533",
            channelColor     = "#bf00ff",
            kernelColor      = "#666699",
            bankColor        = "#ffffff",
            stableArgColor   = "#bf59c6";

        // Fill all clusters (necessary for mouseover)
        var nodes = graph.selectAll("g.node rect, g.cluster rect")
            .filter(function (d) {
                return (d.indexOf("container") == -1 && d != "glbmem" && flattenedNodes[d] &&
                    flattenedNodes[d].type != "kernel" && flattenedNodes[d].type != "component");
            })
            .style("fill-opacity", 0.5)
            .style("fill", "white");

        // Color loop basic blocks
        nodes.filter(function (d) {
            var node = flattenedNodes[d];
            var details = getDetails(node);
            return (node && node.type == "bb" && details && details.Subloops == "No" &&
                (details.Pipelined == "No" ||
                details.II > 1 ||
                (details.II == 1 && details["Fmax Bottlenecks"] == "Yes")));
        })
        .style("fill-opacity", 0.5)
        .style("fill", loopBlockColor)
        .style("stroke-width", 0);

        // Color kernel outlines
        graph.selectAll("g.node rect, g.cluster rect")
            .filter(function (d) {
                return (flattenedNodes[d] && (flattenedNodes[d].type == "kernel" || flattenedNodes[d].type == "component"));
            })
            .style("stroke-width", 2)
            .style("stroke", kernelColor);

        // Select all memsys nodes
        var mem = nodes.filter(function (d) {
            return (flattenedNodes[d] && flattenedNodes[d].type == "memsys");
        }).style("fill", singlePumpColor)
          .style("stroke", singlePumpColor);

        // Color all banks
        var bank = nodes.filter(function (d) {
            return (flattenedNodes[d] && flattenedNodes[d].type == "bank");
        }).style("fill", bankColor)
          .style("stroke", singlePumpColor);

        // Color global memory systems
        mem.filter(function (d) {
                return (flattenedNodes[d] && flattenedNodes[d].global);
            })
            .style("fill", glbmemColor)
            .style("stroke", glbmemColor);

        // Color all stable arguments
        var stable_arg = nodes.filter(function (d) {
            var node = flattenedNodes[d];
            var details = getDetails(node);
            return (node &&
                    node.type == "interface" &&
                    details &&
                    details.Stable === "Yes");
        }).style("fill", stableArgColor)
          .style("stroke", stableArgColor);

        var insts = graph.selectAll("g.nodes circle, g.nodes polygon");

        // Color stallable nodes
        insts.filter(isStallable)
        .style("stroke", loopBlockColor)
        .style("fill", loopBlockColor)
        .style("fill-opacity", 0.6);

        // Color arbitration nodes
        var arbs = nodes.filter (function (d) {
            return (flattenedNodes[d] && flattenedNodes[d].type == "arb" && flattenedNodes[d].name == "ARB");
        }).style("stroke", loopBlockColor)
          .style("fill", loopBlockColor)
          .style("fill-opacity", 0.6);

        insts.filter(function (d) {
            if (!isStallable(d)) return false;
            for (var i = 0; i < flattenedLinks[d].length; i++) {
                var parentFrom = getNode(flattenedLinks[d][i].from);
                var parentTo = getNode(flattenedLinks[d][i].to);
                if (parentFrom.global || parentTo.global) return true;
            }
            return false;
        })
        .style("fill-opacity", 0.5)
        .style("stroke", glbmemColor)
        .style("fill", glbmemColor);

        var connections = graph.selectAll("g.edgePath");

        // Color channel connections
        var channelConnections = connections.filter(function (k) {
            return (flattenedNodes[k.v].type == "channel" ||
                flattenedNodes[k.v].type == "stream" ||
                flattenedNodes[k.w].type == "channel" ||
                flattenedNodes[k.w].type == "stream" ||
                flattenedNodes[k.v].type == "interface");
        });

        channelConnections.selectAll("path")
            .style("stroke", channelColor);

        channelConnections.selectAll("marker")
            .attr({
                "markerUnits": "userSpaceOnUse",
                "preserveAspectRatio": "none",
                "viewBox": "0 0 40 10",
                "refX": 6,
                "markerWidth": 40,
                "markerHeight": 12
            })
            .style("stroke-width", 0);
        channelConnections.selectAll("marker path")
            .attr("style", "fill:" + channelColor + "; opacity: 0.8; stroke-width:0");

        // Color loop connections
        var mergeBranchConnections = connections.filter(function (k) {
            var nodeV = getNode(k.v),
                nodeW = getNode(k.w);

            if ((isMergeOrBranch(k.v) || nodeV.type == "bb") &&
                getDetails(nodeV) &&  getDetails(nodeV)["Loops To"] &&
                (isMergeOrBranch(k.w) || nodeW.type == "bb") &&
                getDetails(nodeV)["Loops To"] == nodeW.id) {
                return true;
            }
            return false;
        });

        // Color MG and BR in loops
        insts.filter(function (d) {
            var node = flattenedNodes[d];
            var bb = flattenedNodes[node.parent];
            var details = getDetails(bb);
            if (node && isMergeOrBranch(d) && details &&
                details.Subloops === "No" &&
                (details.Pipelined == "No" ||
                details.II > 1 ||
                (details.II == 1 && details["Fmax Bottlenecks"] == "Yes"))) {
                node.isHighlighted = true;
                return true;
            }
            node.isHighlighted = false;
            return false;
        })
        .style("stroke", mergeBranchColor)
        .style("fill", mergeBranchColor);

        // Color loop back edges
        mergeBranchConnections.selectAll("path")
            .style("opacity", 0.5)
            .style("stroke", loopEdgeColor);

        // Color highlighted loop back edges
        var loopHighlight = mergeBranchConnections.filter(function (k) {
            return (flattenedNodes[k.v].isHighlighted && flattenedNodes[k.w].isHighlighted);
            });
        loopHighlight.selectAll("path")
            .style("stroke", loopBlockColor);

        // Color loop back edge arrowheads
        mergeBranchConnections.selectAll("marker")
        .style("stroke-width", 0);

        mergeBranchConnections.selectAll("marker path")
            .style("fill", loopEdgeColor)
            .style("stroke-width", 0)
            .style("opacity", 0.8);

        loopHighlight.selectAll("marker path")
            .style("fill", loopBlockColor)
            .style("stroke-width", 0)
            .style("opacity", 0.8);

    }

    // STALL POINT GRAPH
    // --------------------------------------------------------------------------------------------

    // Setup the stall point viewer features
    function setupSPG(graphType) {

        // Add layers menu
        addCheckBox(graphType);
        // Add highlighting for links
        addHighlighting(spgSVG);
        // Add syncing to line and persistence for link highlights
        addClickFunctions(spgSVG);
        // Color link arrowheads
        colorArrowheads(spgSVG);
        // Add tooltips to nodes to display details
        addToolTips(spgSVG);
        // Color basic blocks with loops (also calls colorNodes)
        refreshPersistence(spgSVG);
        // Hide container border
        spgSVG.selectAll("g.cluster rect")
            .filter(function (d) { return d.indexOf("container") != -1 || d == "glbmem"; })
            .style("stroke-width", "0px");

        // Adjust the size of the window before getting the pane dimensions to get accurate scaling
        adjustToWindowEvent();

        var GID = getGID(graphType);

        panelWidth = $(GID)[0].getBoundingClientRect().width - 2 * marginOffset;
        panelHeight = $(GID)[0].getBoundingClientRect().height - 2 * marginOffset;

        graphWidth = spgGroup[0][0].getBoundingClientRect().width + 2 * marginOffset;
        graphHeight = spgGroup[0][0].getBoundingClientRect().height + 2 * marginOffset;
        zoomFitScale = Math.min(panelWidth/graphWidth, panelHeight/graphHeight);

        var offsetX = marginOffset + panelWidth/2 - graphWidth/2 * zoomFitScale; // Offset to center the graph in the middle
        var offsetY = marginOffset + panelHeight/2 - graphHeight/2 * zoomFitScale; // Offset to center the graph in the middle

        // Add zoom and drag
        var zoom_range = [];
        // Calculate the zoom range depending on if the zoomFitScale is greater or less than one
        if (zoomFitScale <= 1) {
            zoom_range = [1, 2 / zoomFitScale];
        } else {
            zoom_range = [1, 2];
        }
            
        zoom = d3.behavior.zoom().scaleExtent(zoom_range).on("zoom", function () {
        
            var GID = getGID(graphType);

            var panelWidth = $(GID)[0].getBoundingClientRect().width - 2 * marginOffset;
            var panelHeight = $(GID)[0].getBoundingClientRect().height - 2 * marginOffset;
            
            zoomFitScale = Math.min(panelWidth/graphWidth, panelHeight/graphHeight);
        
            var offsetX = marginOffset + panelWidth / 2 - graphWidth / 2 * zoomFitScale; // Offset to center the graph in the middle
            var offsetY = marginOffset + panelHeight / 2 - graphHeight / 2 * zoomFitScale; // Offset to center the graph in the middle
        
            var x = d3.event.translate[0] + offsetX * d3.event.scale; 
            var y = d3.event.translate[1] + offsetY * d3.event.scale;

            d3.select(GID).select("g")
                .attr("transform", "translate(" + x + "," + y + ")" +
                                        "scale(" + d3.event.scale * zoomFitScale + ")");
            $('g.cluster rect, g.node circle, g.node rect, g.node polygon').trigger('mouseleave');
        });

        spgSVG.call(zoom);

        // Place the graph in top left corner
        spgGroup.attr("transform", "translate( " + offsetX + ", " + offsetY + ") scale(" + zoomFitScale + ")");
        spgSVG.attr("height", Math.max(spg.graph().height + 40, panelHeight));

        // If memory viewer, then change details pane to be the memory's detail
        if (graphType == "LMEM") {
            // The memory name is clicked, not the bank name
            if (!bankName || !lmemBankNode) {
                changeDivContent(0, getHTMLDetailsFromJSON(getDetails(lmemNode), lmemNode.name));
            } else {
                changeDivContent(0, getHTMLDetailsFromJSON(getDetails(lmemBankNode), lmemNode.name));
            }
        }
    }

    // Create nodes for stall point
    function createNodes(group, nodes, graphType, kernelName, lmemName, bankList) {
        var isInst = false;
        var insts = [];
        var index = 0;
        var name = "";

        nodes.forEach(function (n) {

            // Only add nodes which are visible
            if (n.hasOwnProperty("visible") && !n.visible) return;

            // Add nodes to those in graph (instructions added after collapsing)
            if (n.type != "inst") flattenedNodes[getUniqueNodeName(n.id)] = n;

            if (group !== "") n.parent = group;

            // Collect node types for link filtering checkboxes
            if (nodeTypes.indexOf(n.type) == -1) nodeTypes.push(n.type);

            if (n.children) {

                // Set node
                if (n.type == "kernel" || n.type == "component") {
                    spg.setNode(getNodeID(n), { label: n.type + " " + n.name, clusterLabelPos: "top", paddingTop: containerPadding });
                } else if (bankList && bankList.indexOf(n.name) == -1)  {
                    // Set the collapsed bank to not have any padding and default width/height
                    spg.setNode(getNodeID(n), { label: n.name, clusterLabelPos: "top",  width: nodeWidth, height: nodeHeight });
                } else if (graphType == "CSPV" && n.name == "Global Memory" && !seenGlobal) {
                    // Don't render the global memory if no instructions sees it 
                    return; 
                } else {
                    spg.setNode(getNodeID(n), { label: n.name, clusterLabelPos: "top", paddingTop: containerPadding,  width: nodeWidth, height: nodeHeight });
                }

                // Place in correct group
                if (n.name == "Global Memory") {
                    spg.setNode("glbmem", {});
                    spg.setParent(getNodeID(n), "glbmem");
                } else if (group !== "") {
                    spg.setParent(getNodeID(n), group);
                } else {
                    spg.setParent(getNodeID(n), "container");
                }

                // If it's a bank node for local mem, check if it's in bank list
                if (graphType == "LMEM" && n.type == "bank") {
                    if (bankList.indexOf(n.name) != -1) createNodes(getNodeID(n), n.children, graphType, kernelName, lmemName, bankList);
                }
                else {
                    // Create nodes from children
                    createNodes(getNodeID(n), n.children, graphType, kernelName, lmemName, bankList);
                }

            } else {

                // Create regular node, inst, or channel
                if (n.type == "inst") {
                    if (graphType == "SPV" || graphType == "CSPV") {
                        index = checkInst(insts, n, true);
                        if (index == -1) {
                            n.count = 1;
                            insts.push(n);
                        } else {
                            insts[index].count += 1;
                        }
                        // Only check if the instruction goes to a Global Memory if we haven't seen the Global Memory yet
                        if (!seenGlobal) {
                            var d = getNodeID(n);
                            for (var i = 0; i < linkMap[d].length; i++) {
                                var parentFrom = nodeMap[getUniqueNodeName(linkMap[d][i].from)];
                                var parentTo = nodeMap[getUniqueNodeName(linkMap[d][i].to)];
                                if (parentFrom.global || parentTo.global) seenGlobal = true;
                            }
                        }
                    } else if (graphType == "LMEM") {
                        insts.push(n);
                    }
                    isInst = true;
                } else if (n.type == "channel" || n.type == "stream" || n.type == "interface") {
                    if (n.visible || !n.hasOwnProperty("visible")) {
                        // If name length > 10, truncate to the form "abcde...vwxyz"
                        name = n.name;
                        if (n.name.length > 13) name = name.substring(0, 5) + "..." + name.substring(name.length - 5, name.length);
                        if (n.count > 1) name += " (x" + n.count + ")";
                        var chanWidth = name.length * 4 + 2;
                        spg.setNode(getNodeID(n), { label: name, width: chanWidth, height: nodeHeight });
                        if (group === "") spg.setParent(getNodeID(n), "container");
                        else spg.setParent(getNodeID(n), group);
                    }
                } else if (n.type == "memsys") {
                    // Check if this memsys needs to be rendered for HLS Component Viewer
                    var memsysLinkList = linkMap[getNodeID(n)];
                    if (graphType == "CSPV" && (getNode(group) && getNode(group).name == "Global Memory") && !isGlobMemsysInComp(memsysLinkList, kernelName)) {
                        return;
                    }

                    name = n.name;
                    if (n.details) {
                      var numbanks = /(\d+)/.exec(getDetails(n)["Number of banks"]);
                      if (numbanks !== null && numbanks !== undefined) name += " [" + numbanks[0] + "]";
                      var replication = /(\d+)/.exec(getDetails(n)["Total replication"]);
                      if (replication !== null && replication !== undefined && replication[0] > 1) name += " (x" + replication[0] + ")";
                    }
                    var padding = name.length < 8 ? 10 : 2; // Padding for memsys with very short names so that "Global Memory is not cut off"
                    var memsysWidth = name.length*5 + padding;
                    spg.setNode(getNodeID(n), { label: name, clusterLabelPos: "top", paddingTop: containerPadding, width: memsysWidth});
                    spg.setParent(getNodeID(n), group);
                } else if (n.type == "port") {
                    spg.setNode(getNodeID(n), { label: n.name, shape: "circle", width: portRadius, height: portRadius });
                    spg.setParent(getNodeID(n), group);
                } else if (n.type == "bb") {
                    // If name length > 10, truncate to the form "abcde...vwxyz"
                    name = n.name;
                    var bbWidth = name.length * 5 + 2;
                    spg.setNode(getNodeID(n), { label: n.name, width: bbWidth, height: nodeHeight });
                    spg.setParent(getNodeID(n), group);
                } else {
                    spg.setNode(getNodeID(n), { label: n.name, width: nodeWidth, height: nodeHeight });

                    if (n.name == "Global Memory") {
                        spg.setNode("glbmem", {});
                        spg.setParent(getNodeID(n), "glbmem");
                    } else if (group !== "") {
                        spg.setParent(getNodeID(n), group);
                    } else {
                        spg.setParent(getNodeID(n), "container");
                    }
                }
            }

        });

        if (isInst) setInsts(group, insts);
    }

    // Create links for stall point
    function createLinks(links) {
        links.forEach(function (lnk) {
            if (flattenedNodes.hasOwnProperty(getUniqueNodeName(lnk.from)) && flattenedNodes.hasOwnProperty(getUniqueNodeName(lnk.to))) {

                if (!flattenedLinks[getUniqueNodeName(lnk.from)]) flattenedLinks[getUniqueNodeName(lnk.from)] = [];
                flattenedLinks[getUniqueNodeName(lnk.from)].push(lnk);

                if (!flattenedLinks[getUniqueNodeName(lnk.to)]) flattenedLinks[getUniqueNodeName(lnk.to)] = [];
                flattenedLinks[getUniqueNodeName(lnk.to)].push(lnk);

                if (graphType == "LMEM") {
                    // For these specific cases, reverse the edge direction when passing into Dagre-D3 engine to help alignment of the nodes
                    // 1. INST <-- ARB. Render it as INST --> ARB
                    // 2. INST <-- Port. Render it as INST --> Port
                    // 3. ARB <-- Port. Render it as ARB --> Port
                    if ((getNode(lnk.to).type == "inst" && getNode(lnk.from).type == "arb") ||
                        (getNode(lnk.to).type == "inst" && getNode(lnk.from).type == "port") ||
                        (getNode(lnk.to).type == "arb" && getNode(lnk.from).type == "port")) {
                        spg.setEdge(getUniqueNodeName(lnk.to), getUniqueNodeName(lnk.from), { arrowhead: "normal", lineInterpolate: "basis", weight: 1 });
                    } else {
                        // Render the edge in the normal direction as specified in the JSON
                        spg.setEdge(getUniqueNodeName(lnk.from), getUniqueNodeName(lnk.to), { arrowhead: "normal", lineInterpolate: "basis", weight: 1 });
                    }
                } else if ((graphType == "SPV") || (graphType == "CSPV")) {
                    // Reverse the edge when:
                    // 4. LD <-- MemSys. Still render in that direction
                    // 5. Loop <-- LoopEnd. Still render in that direction
                    if (getNode(lnk.to).type == "inst" && getNode(lnk.from).type == "memsys") {
                        spg.setEdge(getUniqueNodeName(lnk.to), getUniqueNodeName(lnk.from), { arrowhead: "reversed", lineInterpolate: "basis", weight: 1 });
                    } else if (getDetails(getNode(lnk.to)) && getDetails(getNode(lnk.to)).hasOwnProperty("Loops To") && getDetails(getNode(lnk.to))["Loops To"] == getNode(lnk.from).id) {
                        spg.setEdge(getUniqueNodeName(lnk.to), getUniqueNodeName(lnk.from), { arrowhead: "reversed", lineInterpolate: "basis", weight: 1 });
                    } else if (getNode(lnk.to).type == "inst" && getNode(lnk.from).type == "channel") {
                        spg.setEdge(getUniqueNodeName(lnk.to), getUniqueNodeName(lnk.from), { arrowhead: "reversed", lineInterpolate: "basis", weight: 1 });
                    } else if (lnk.to == lnk.from) {
                        // Reverse the arrowhead for self-loops for blocks so that it points back up instead of downward
                        spg.setEdge(getUniqueNodeName(lnk.from), getUniqueNodeName(lnk.to), { arrowhead: "reversed", lineInterpolate: "basis", weight: 1 });
                    } else {
                        spg.setEdge(getUniqueNodeName(lnk.from), getUniqueNodeName(lnk.to), { arrowhead: "normal", lineInterpolate: "basis", weight: 1 });
                    }
                }
            }
        });
    }

     // Check if two insts are the same
    function checkInst(insts, node, isSPG) {
        var index = 0;
        for (var i = 0; i < insts.length; i++) {
            if (   node.type == "inst" &&
                node.name == insts[i].name &&
                verifyDetails(node, insts[i]) &&
                verifyLinks(insts[i], node, isSPG)) { return index; }
            index++;
        }

        return -1;
    }

    // Verify details and debug information between nodes
    function verifyDetails(a, b) {
      var aDetails = getDetails(a);
      var bDetails = getDetails(b);

      // Verify that details sections match
      if (aDetails && bDetails) {
          var akeys = Object.keys(aDetails);
          var bkeys = Object.keys(bDetails);
          if (akeys.length != bkeys.length) return false;

          for (var i = 0; i < akeys.length; ++i) {
              var key = akeys[i];
              if (!bDetails.hasOwnProperty(key) || aDetails[key] != bDetails[key]) return false;
          }
      } else if (aDetails || bDetails) {
          return false;
      }
      
      // Verify that debug sections match
      var aLength = (a.debug) ? ((a.debug.length) ? a.debug[0].length : 0) : 0;
      var bLength = (b.debug) ? ((b.debug.length) ? b.debug[0].length : 0) : 0;
      
      if (aLength === bLength)
        return (!aLength || (a.debug[0][0].filename === b.debug[0][0].filename &&
                             a.debug[0][0].line     === b.debug[0][0].line));
      else
        return false;
    }

    // Verify that links are the same between duplicates
    function verifyLinks(inst, node, isSPG) {
        var instLinks = linkMap[getNodeID(inst)];
        var nodeLinks = linkMap[getNodeID(node)];
        var found = false;

        if (!instLinks && !nodeLinks) return true;
        else if (!instLinks || !nodeLinks) return false;

        for (var j = 0; j < instLinks.length; j++) {
            found = false;
            var i;
            if (instLinks[j].from == inst.id) {
                for (i = 0; i < nodeLinks.length; i++) {
                    if ( nodeLinks[i].from == node.id &&
                        nodeLinks[i].to == instLinks[j].to ) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            } else if (instLinks[j].to == inst.id) {
                for (i = 0; i < nodeLinks.length; i++) {
                    if ( nodeLinks[i].from == instLinks[j].from &&
                        nodeLinks[i].to == node.id ) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
        }

        return true;
    }

    // Set insts - including duplicates
    function setInsts(group, insts) {
        var name;

        insts.forEach(function (n) {
            flattenedNodes[getUniqueNodeName(n.id)] = n;

            name = getLabelName(n.name);
            if (n.hasOwnProperty('count') && n.count > 1) name += " (x" + n.count + ")";

            if (getNode(n.id).name == "end" || getNode(n.id).name == "loop end") spg.setNode(getUniqueNodeName(n.id), { label: name, shape: "diamond", width: 1, height: 1 });
            else spg.setNode(getUniqueNodeName(n.id), { label: name, shape: "circle", width: 1, height: 1 });

            if (group !== "") spg.setParent(getUniqueNodeName(n.id), group);
            else spg.setParent(getUniqueNodeName(n.id), "container");
        });
    }

    // Insert html for layer menu
    function addCheckBox(graphType) {
        var menu = "";
        // var graph = graphType == "SPV" ? "spv_graph" : "lmem_graph";
        var graph = getGraphName(graphType);

        menu += "<form id='layerMenu'>";

        menu += "<button title=\"Zoom to fit\" type='button' onclick='" + graph + ".zoomToFit()' style=\"padding:0\">Reset Zoom</button><button title=\"Remove highlights\" type='button' onclick='" + graph + ".removeHighlights()' style=\"padding:0\">Clear Selection</button>&nbsp&nbsp&nbsp&nbsp";

        // Add checkbox for connections types for system viewer only
        if ((graphType == "SPV") || (graphType == "CSPV")) {
            nodeTypes.forEach(function (nt) {
                switch (nt) {
                    case "inst": menu += "<input id='linkCheck' type='checkbox' checked='checked' name='linkType' value='" + nt + "' onClick='" + graph + ".resetVisibleLinks()'>&nbspControl&nbsp&nbsp";
                        break;
                    case "memsys": menu += "<input id='linkCheck' type='checkbox' checked='checked' name='linkType' value='" + nt + "' onClick='" + graph + ".resetVisibleLinks()'>&nbspMemory&nbsp&nbsp";
                        break;
                    case "channel": menu += "<input id='linkCheck' type='checkbox' checked='checked' name='linkType' value='" + nt + "' onClick='" + graph + ".resetVisibleLinks()'>&nbspChannels&nbsp&nbsp";
                        break;
                    case "stream": menu += "<input id='linkCheck' type='checkbox' checked='checked' name='linkType' value='" + nt + "' onClick='" + graph + ".resetVisibleLinks()'>&nbspStreams&nbsp&nbsp";
                        break;
                }
            });
        }

        menu += "</form>";

        if (graphType == "SPV") {
            $("#layers").html(menu);
        } else if (graphType == "LMEM") {
            $("#layers-lmem").html(menu);
        } else if (graphType == "CSPV") {
            $("#layers-comp").html(menu);
        }

    }

    // Reset visibility on links after checked and unchecked in layers menu
    this.resetVisibleLinks = function () {

        d3.selectAll("g.edgePath path").style("visibility", "visible");
        d3.selectAll("g.node rect, g.label").style("visibility", "visible");
        refreshPersistence(spgSVG);
        clickDown = null;
        invisNodes = [];
        invisLinks = [];

        $('#layerMenu input').each(function () {
            var tempBox = (this);

            if (!tempBox.checked) {
                switch (tempBox.getAttribute("value")) {

                    // Remove streams and links to channels
                    case "stream":
                        spgSVG.selectAll("g.edgePath path").filter(function (k) {
                                if (flattenedNodes[k.v].type == "stream" || flattenedNodes[k.w].type == "stream") {
                                    invisLinks.push(k);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");

                        spgSVG.selectAll("g.node rect, g.nodes .label").filter(function (n) {
                                if (flattenedNodes[n].type == "stream") {
                                    if (invisNodes.indexOf(n) == -1) invisNodes.push(n);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");
                        break;

                    // Remove channels and links to channels
                    case "channel":
                        spgSVG.selectAll("g.edgePath path").filter(function (k) {
                                if (flattenedNodes[k.v].type == "channel" || flattenedNodes[k.w].type == "channel") {
                                    invisLinks.push(k);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");

                        spgSVG.selectAll("g.node rect, g.nodes .label").filter(function (n) {
                                if (flattenedNodes[n].type == "channel") {
                                    if (invisNodes.indexOf(n) == -1) invisNodes.push(n);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");
                        break;

                        // Remove links between instructions
                    case "inst":
                        spgSVG.selectAll("g.edgePath path").filter(function (k) {
                                if (flattenedNodes[k.v].type == "inst" && flattenedNodes[k.w].type == "inst") {
                                    invisLinks.push(k);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");
                        break;

                        // Remove all links to and from memory
                    case "memsys":
                        spgSVG.selectAll("g.edgePath path").filter(function (k) {
                                if (flattenedNodes[k.v].type == "memsys" || flattenedNodes[k.w].type == "memsys") {
                                    invisLinks.push(k);
                                    return true;
                                }
                                return false;
                            })
                            .style("visibility", "hidden");
                        break;
                }
            }

        });
    };

    // Remove highlighting
    this.removeHighlights = function () {
        refreshPersistence(spgSVG);
        clickDown = null;
    };

    // Zoom to fit function
    this.zoomToFit = function () {
        var GID = getGID(graphType);
        
        var panelWidth = $(GID)[0].getBoundingClientRect().width - 2 * marginOffset;
        var panelHeight = $(GID)[0].getBoundingClientRect().height - 2 * marginOffset;
        
        zoomFitScale = Math.min(panelWidth/graphWidth, panelHeight/graphHeight);
            
        var offsetX = marginOffset + panelWidth/2 - graphWidth/2 * zoomFitScale; // Offset to center the graph in the middle
        var offsetY = marginOffset + panelHeight/2 - graphHeight/2 * zoomFitScale; // Offset to center the graph in the middle

        // Reset the graph's zoom level

        spgGroup.transition()

                .duration(500)

                .attr("transform", "translate( " + offsetX + ", " + offsetY + ") scale(" + zoomFitScale + ")");

        // Reset the zoom object scale level and translate so that subsequent pan and zoom behaves like from beginning
        zoom.scale(1);
        zoom.translate([0,0]);
    };

    // Get the GID depending on the graphType
    function getGID(type) {
      switch(type) {
          case "SPV": return "#SPG";
          case "CSPV": return "#CSPG";
          case "LMEM": return "#LMEMG";
      }
    }

    // Get the graph name used in main.js
    function getGraphName(type) {
      switch(type) {
          case "SPV": return "spv_graph";
          case "LMEM": return "lmem_graph";
          case "CSPV": return "cspv_graph";
      }
    }

    // Check that the edge links to an instruction to that component
    function isGlobMemsysInComp(memsysLinkList, kernelName) {
        for (var i = 0; i < memsysLinkList.length; i++) {
            var nodeLinkTo = getNode(memsysLinkList[i].to);
            var nodeLinkFrom = getNode(memsysLinkList[i].from);
            var compNode;
            if (nodeLinkTo && nodeLinkTo.type == "inst") {
                compNode = getCompNodeFromInstNode(nodeLinkTo);
                if (compNode.name == kernelName) {
                    return true;
                }
            } else if (nodeLinkFrom && nodeLinkFrom.type == "inst") {
                compNode = getCompNodeFromInstNode(nodeLinkFrom);
                if (compNode.name == kernelName) {
                    return true;
                }
            }
        }
        return false;
    }

    function getCompNodeFromInstNode(node) {
        // Go up 2 hierarchies
        // Component -> basicblock -> instruction node
        var bbNode = getNode(node.parent);
        var compNode = getNode(bbNode.parent);
        return compNode;
    }

    // return details object or null
    function getDetails(node) {
        if (!node || !node.details) return null;
        warn(node.details.length <= 1, "Details should not have more than 1 item!");
        return node.details[0];
    }
    
}
