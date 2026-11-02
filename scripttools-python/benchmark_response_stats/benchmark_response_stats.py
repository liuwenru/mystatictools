#!/usr/bin/env python3

import argparse
import math
import statistics
import sys
from collections import defaultdict


class ChineseArgumentParser(argparse.ArgumentParser):
    def format_help(self):
        return (
            super().format_help()
            .replace("usage:", "用法:", 1)
            .replace("positional arguments:", "位置参数:")
            .replace("optional arguments:", "选项:")
            .replace("options:", "选项:")
        )


def percentile_nearest_rank(sorted_values, percentile):
    index = math.ceil(len(sorted_values) * percentile) - 1
    return sorted_values[index]


def calculate_tail_metrics(sorted_values, tail_ratio, total_time, average):
    tail_count = math.floor(len(sorted_values) * tail_ratio)
    if tail_count == 0:
        return average, 0.0

    tail_time = sum(sorted_values[-tail_count:])
    remaining_values = sorted_values[:-tail_count]
    average_without_tail = sum(remaining_values) / len(remaining_values)
    time_contribution = tail_time / total_time * 100 if total_time else 0.0
    return average_without_tail, time_contribution


def load_response_times(file_path):
    grouped_by_url = defaultdict(list)
    grouped_by_server = defaultdict(list)
    skipped = 0

    with open(file_path, "r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            fields = line.split()
            if not fields:
                continue
            if len(fields) < 3:
                skipped += 1
                print(
                    "warning: skipped line {}: expected at least 3 columns".format(
                        line_number
                    ),
                    file=sys.stderr,
                )
                continue

            try:
                response_time = float(fields[2])
            except ValueError:
                skipped += 1
                print(
                    "warning: skipped line {}: invalid response time {!r}".format(
                        line_number, fields[2]
                    ),
                    file=sys.stderr,
                )
                continue

            grouped_by_url[fields[0]].append(response_time)
            grouped_by_server[fields[1]].append(response_time)

    return grouped_by_url, grouped_by_server, skipped


def print_statistics(grouped, group_name, key_last=False):
    if key_last:
        headers = (
            "count", "average", "median", "p95", "p99",
            "avg_no_top1", "avg_no_top5", "top1_time_pct",
            "top5_time_pct", "top5_avg_lift_pct", group_name,
        )
    else:
        headers = (
            group_name, "count", "average", "median", "p95", "p99",
            "avg_no_top1", "avg_no_top5", "top1_time_pct",
            "top5_time_pct", "top5_avg_lift_pct",
        )
    rows = []
    for key in sorted(grouped):
        values = sorted(grouped[key])
        count = len(values)
        total_time = sum(values)
        average = total_time / count
        median = statistics.median(values)
        p95 = percentile_nearest_rank(values, 0.95)
        p99 = percentile_nearest_rank(values, 0.99)
        average_without_top1, top1_time_contribution = calculate_tail_metrics(
            values, 0.01, total_time, average
        )
        average_without_top5, top5_time_contribution = calculate_tail_metrics(
            values, 0.05, total_time, average
        )
        if average_without_top5:
            top5_average_lift = (
                (average - average_without_top5) / average_without_top5 * 100
            )
            top5_average_lift_text = "{:.2f}%".format(top5_average_lift)
        elif average == 0:
            top5_average_lift_text = "0.00%"
        else:
            top5_average_lift_text = "N/A"

        metrics = (
            str(count), "{:.3f}".format(average), "{:.3f}".format(median),
            "{:.3f}".format(p95), "{:.3f}".format(p99),
            "{:.3f}".format(average_without_top1),
            "{:.3f}".format(average_without_top5),
            "{:.2f}%".format(top1_time_contribution),
            "{:.2f}%".format(top5_time_contribution),
            top5_average_lift_text,
        )
        rows.append(metrics + (key,) if key_last else (key,) + metrics)

    widths = [
        max(len(headers[index]), max(len(row[index]) for row in rows))
        for index in range(len(headers))
    ]
    alignments = [">"] * len(headers)
    alignments[-1 if key_last else 0] = "<"
    row_format = "\t".join(
        "{{:{}{}}}".format(alignment, width)
        for alignment, width in zip(alignments, widths)
    )
    print(row_format.format(*headers))
    for row in rows:
        print(row_format.format(*row))


def main():
    parser = ChineseArgumentParser(
        description=(
            "分别按请求 URL 和响应服务器对响应时间进行分组，统计平均值、中位数、"
            "P95、P99 以及长尾请求的影响。"
        ),
        epilog=(
            "输入文件格式（使用空白字符分隔）：\n"
            "  第一列：请求 URL\n"
            "  第二列：响应服务器地址\n"
            "  第三列：响应时间\n"
            "\n"
            "输入示例：\n"
            "  /v1/chat/completions  192.155.1.153:15001  1.211\n"
            "\n"
            "长尾指标说明：\n"
            "  avg_no_top1：去掉最慢 1% 请求后的平均响应时间\n"
            "  avg_no_top5：去掉最慢 5% 请求后的平均响应时间\n"
            "  top1_time_pct：最慢 1% 请求占总响应耗时的比例\n"
            "  top5_time_pct：最慢 5% 请求占总响应耗时的比例\n"
            "  top5_avg_lift_pct：最慢 5% 请求导致平均响应时间上升的比例\n"
            "  长尾样本数按 floor(样本数 * 比例) 向下取整。"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        add_help=False,
    )
    parser.add_argument(
        "input_file",
        metavar="输入文件",
        help="包含请求 URL、响应服务器地址和响应时间三列的数据文件",
    )
    parser.add_argument("-h", "--help", action="help", help="显示此帮助信息并退出")
    args = parser.parse_args()

    try:
        grouped_by_url, grouped_by_server, skipped = load_response_times(args.input_file)
    except (OSError, UnicodeError) as error:
        parser.error(str(error))

    if not grouped_by_url:
        parser.error("no valid records found")

    print("=== Grouped by request URL ===")
    print_statistics(grouped_by_url, "url", key_last=True)
    print()
    print("=== Grouped by response server ===")
    print_statistics(grouped_by_server, "server")

    print(
        "total={} url_groups={} server_groups={} skipped={}".format(
            sum(len(values) for values in grouped_by_url.values()),
            len(grouped_by_url),
            len(grouped_by_server),
            skipped,
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
